import Foundation
import os.log

// ═══════════════════════════════════════════════════════════════════
// MARK: - NetworkGameService
// ═══════════════════════════════════════════════════════════════════
//
// Сетевой сервис для мультиплеера «Крестики-Нолики».
// Использует URLSessionWebSocketTask для двунаправленной связи.
//
// Архитектура устойчивости (Chaos Simulator):
// ─────────────────────────────────────────────
// 1. Exponential Backoff при переподключении (1с → 2с → 4с → 8с → 16с)
// 2. Максимум 5 попыток переподключения, затем fallback на ИИ
// 3. Ping/Pong heartbeat каждые 10 секунд для обнаружения «мёртвого» соединения
// 4. Таймер матчмейкинга 15с с автоматическим fallback на Minimax-бота
// 5. Все публичные колбэки изолированы на @MainActor
// 6. Слабые ссылки (weak self) во всех замыканиях для предотвращения retain cycle
// 7. Атомарное управление состоянием через actor-подобную изоляцию
//
// ═══════════════════════════════════════════════════════════════════

// MARK: - Состояние соединения

/// Состояние WebSocket-соединения
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case matchmaking
    case inRoom(roomId: String)
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

// MARK: - Делегат сервиса

/// Протокол для оповещения ViewModel о сетевых событиях.
/// Все методы вызываются на MainActor.
@MainActor
public protocol NetworkGameDelegate: AnyObject {
    /// Состояние соединения изменилось
    func networkService(_ service: NetworkGameService, didChangeState state: ConnectionState)
    
    /// Соперник найден, комната создана
    func networkService(_ service: NetworkGameService, didMatchWith opponent: String, roomId: String, assignedPlayer: Player)
    
    /// Соперник сделал ход
    func networkService(_ service: NetworkGameService, didReceiveMove move: MoveMessage)
    
    /// Получена полная синхронизация состояния (после переподключения)
    func networkService(_ service: NetworkGameService, didReceiveSync sync: GameStateSync)
    
    /// Соперник отключился
    func networkService(_ service: NetworkGameService, opponentDisconnectedInRoom roomId: String)
    
    /// Таймаут матчмейкинга — соперник не найден за 15 секунд
    func networkServiceMatchmakingTimedOut(_ service: NetworkGameService)
    
    /// Критическая ошибка соединения (после исчерпания попыток переподключения)
    func networkService(_ service: NetworkGameService, didFailWithError error: NetworkGameServiceError)
}

// MARK: - Ошибки сервиса

/// Перечисление ошибок сетевого сервиса
public enum NetworkGameServiceError: Error, Sendable, CustomStringConvertible {
    case invalidURL
    case connectionFailed(underlying: String)
    case encodingFailed(underlying: String)
    case decodingFailed(underlying: String)
    case unexpectedMessageType(String)
    case serverError(code: Int, message: String)
    case reconnectionExhausted
    case alreadyConnected
    
    public var description: String {
        switch self {
        case .invalidURL:
            return "Некорректный URL сервера"
        case .connectionFailed(let msg):
            return "Ошибка соединения: \(msg)"
        case .encodingFailed(let msg):
            return "Ошибка кодирования сообщения: \(msg)"
        case .decodingFailed(let msg):
            return "Ошибка декодирования сообщения: \(msg)"
        case .unexpectedMessageType(let type):
            return "Неожиданный тип сообщения: \(type)"
        case .serverError(let code, let message):
            return "Ошибка сервера [\(code)]: \(message)"
        case .reconnectionExhausted:
            return "Все попытки переподключения исчерпаны"
        case .alreadyConnected:
            return "Соединение уже установлено"
        }
    }
}

// MARK: - Конфигурация

/// Конфигурация параметров сетевого сервиса
public struct NetworkConfig: Sendable {
    /// URL WebSocket-сервера
    public let serverURL: URL
    /// Таймаут матчмейкинга (секунды)
    public let matchmakingTimeout: TimeInterval
    /// Максимальное количество попыток переподключения
    public let maxReconnectAttempts: Int
    /// Базовая задержка переподключения (секунды), удваивается с каждой попыткой
    public let baseReconnectDelay: TimeInterval
    /// Интервал ping/pong heartbeat (секунды)
    public let heartbeatInterval: TimeInterval
    
    public init(
        serverURL: URL,
        matchmakingTimeout: TimeInterval = 15.0,
        maxReconnectAttempts: Int = 5,
        baseReconnectDelay: TimeInterval = 1.0,
        heartbeatInterval: TimeInterval = 10.0
    ) {
        self.serverURL = serverURL
        self.matchmakingTimeout = matchmakingTimeout
        self.maxReconnectAttempts = maxReconnectAttempts
        self.baseReconnectDelay = baseReconnectDelay
        self.heartbeatInterval = heartbeatInterval
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - NetworkGameService
// ═══════════════════════════════════════════════════════════════════

public final class NetworkGameService: Sendable {
    
    // MARK: - Константы
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TicTacToeCore",
        category: "NetworkGameService"
    )
    
    // MARK: - Конфигурация
    
    public let config: NetworkConfig
    public let playerId: String
    public let displayName: String
    
    // MARK: - Делегат (MainActor, weak)
    
    @MainActor
    public weak var delegate: NetworkGameDelegate?
    
    // MARK: - Внутреннее состояние (actor-like isolation через serial queue)
    
    /// Изолированное состояние, доступное только через actor
    private let state: ServiceState
    
    /// Actor для потокобезопасного управления внутренним состоянием
    private actor ServiceState {
        var connectionState: ConnectionState = .disconnected
        var webSocketTask: URLSessionWebSocketTask?
        var urlSession: URLSession?
        var receiveTask: Task<Void, Never>?
        var heartbeatTask: Task<Void, Never>?
        var matchmakingTimerTask: Task<Void, Never>?
        var reconnectAttempt: Int = 0
        var currentRoomId: String?
        var intentionalDisconnect: Bool = false
        var lastServerURL: URL?
        
        func setConnectionState(_ newState: ConnectionState) {
            connectionState = newState
        }
        
        func getConnectionState() -> ConnectionState {
            connectionState
        }
        
        func setWebSocket(_ task: URLSessionWebSocketTask?, session: URLSession?, url: URL?) {
            webSocketTask = task
            urlSession = session
            lastServerURL = url
        }
        
        func getWebSocket() -> URLSessionWebSocketTask? {
            webSocketTask
        }
        
        func setReceiveTask(_ task: Task<Void, Never>?) {
            receiveTask?.cancel()
            receiveTask = task
        }
        
        func setHeartbeatTask(_ task: Task<Void, Never>?) {
            heartbeatTask?.cancel()
            heartbeatTask = task
        }
        
        func setMatchmakingTimer(_ task: Task<Void, Never>?) {
            matchmakingTimerTask?.cancel()
            matchmakingTimerTask = task
        }
        
        func setCurrentRoom(_ roomId: String?) {
            currentRoomId = roomId
        }
        
        func getCurrentRoom() -> String? {
            currentRoomId
        }
        
        func incrementReconnect() -> Int {
            reconnectAttempt += 1
            return reconnectAttempt
        }
        
        func resetReconnect() {
            reconnectAttempt = 0
        }
        
        func getReconnectAttempt() -> Int {
            reconnectAttempt
        }
        
        func setIntentionalDisconnect(_ value: Bool) {
            intentionalDisconnect = value
        }
        
        func isIntentionalDisconnect() -> Bool {
            intentionalDisconnect
        }
        
        func getLastServerURL() -> URL? {
            lastServerURL
        }
        
        /// Полная очистка всех ресурсов
        func teardown() {
            receiveTask?.cancel()
            receiveTask = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            matchmakingTimerTask?.cancel()
            matchmakingTimerTask = nil
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            urlSession?.invalidateAndCancel()
            urlSession = nil
            currentRoomId = nil
            reconnectAttempt = 0
        }
    }
    
    // MARK: - Инициализатор
    
    public init(config: NetworkConfig, playerId: String, displayName: String) {
        self.config = config
        self.playerId = playerId
        self.displayName = displayName
        self.state = ServiceState()
    }
    
    deinit {
        // deinit не может быть async, поэтому планируем очистку через Task
        let stateRef = state
        Task {
            await stateRef.teardown()
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Публичный API
    // ═══════════════════════════════════════════════════════════════
    
    /// Подключиться к серверу и начать поиск игры (автоматический матчмейкинг)
    public func findGame() async {
        let currentState = await state.getConnectionState()
        guard currentState == .disconnected || currentState == .failed(reason: "") || {
            if case .failed = currentState { return true }
            return currentState == .disconnected
        }() else {
            await notifyError(.alreadyConnected)
            return
        }
        
        await connect()
        
        // После подключения отправляем запрос на матчмейкинг
        let connState = await state.getConnectionState()
        guard connState == .connected else { return }
        
        await updateConnectionState(.matchmaking)
        
        let request = MatchmakingRequest(
            playerId: playerId,
            displayName: displayName
        )
        
        await send(type: .matchmakingRequest, content: request)
        await startMatchmakingTimer()
    }
    
    /// Подключиться к комнате по коду (Room ID)
    public func joinRoom(roomId: String) async {
        await connect()
        
        let connState = await state.getConnectionState()
        guard connState == .connected else { return }
        
        let request = JoinRoomRequest(
            playerId: playerId,
            roomId: roomId,
            displayName: displayName
        )
        
        await send(type: .joinRoom, content: request)
    }
    
    /// Отправить ход соперника
    public func sendMove(cellIndex: Int, player: Player) async {
        guard let roomId = await state.getCurrentRoom() else {
            Self.logger.warning("Попытка отправить ход без активной комнаты")
            return
        }
        
        let move = MoveMessage(
            roomId: roomId,
            player: player,
            cellIndex: cellIndex
        )
        
        await send(type: .move, content: move)
    }
    
    /// Принудительное отключение
    public func disconnect() async {
        Self.logger.info("Принудительное отключение от сервера")
        await state.setIntentionalDisconnect(true)
        await state.teardown()
        await updateConnectionState(.disconnected)
    }
    
    /// Текущее состояние соединения
    public func currentConnectionState() async -> ConnectionState {
        await state.getConnectionState()
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Подключение к WebSocket
    // ═══════════════════════════════════════════════════════════════
    
    private func connect() async {
        await state.setIntentionalDisconnect(false)
        await state.resetReconnect()
        await updateConnectionState(.connecting)
        
        Self.logger.info("Подключение к серверу: \(self.config.serverURL.absoluteString)")
        
        // Конфигурация URLSession с таймаутами
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30     // Таймаут запроса
        sessionConfig.timeoutIntervalForResource = 300   // Таймаут ресурса
        sessionConfig.waitsForConnectivity = true        // Ожидание сети
        
        let session = URLSession(configuration: sessionConfig)
        let wsTask = session.webSocketTask(with: config.serverURL)
        
        await state.setWebSocket(wsTask, session: session, url: config.serverURL)
        
        wsTask.resume()
        
        // Проверяем успешность подключения через первый ping
        do {
            try await wsTask.sendPing()
            Self.logger.info("WebSocket подключён успешно")
            await updateConnectionState(.connected)
            await startReceiving()
            await startHeartbeat()
        } catch {
            Self.logger.error("Ошибка подключения: \(error.localizedDescription)")
            await handleDisconnection(error: error)
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Приём сообщений
    // ═══════════════════════════════════════════════════════════════
    
    /// Запускает бесконечный цикл приёма WebSocket-сообщений
    private func startReceiving() async {
        let task = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                guard let wsTask = await self.state.getWebSocket() else {
                    break
                }
                
                do {
                    let message = try await wsTask.receive()
                    await self.handleReceivedMessage(message)
                } catch {
                    // Ошибка приёма = разрыв соединения
                    if !Task.isCancelled {
                        Self.logger.error("Ошибка приёма: \(error.localizedDescription)")
                        await self.handleDisconnection(error: error)
                    }
                    break
                }
            }
        }
        
        await state.setReceiveTask(task)
    }
    
    /// Обработка полученного WebSocket-сообщения
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        
        switch message {
        case .data(let d):
            data = d
        case .string(let text):
            guard let textData = text.data(using: .utf8) else {
                Self.logger.warning("Не удалось декодировать текстовое сообщение в UTF-8")
                return
            }
            data = textData
        @unknown default:
            Self.logger.warning("Получен неизвестный тип WebSocket-сообщения")
            return
        }
        
        // Декодируем конверт
        let envelope: NetworkEnvelope
        do {
            envelope = try JSONDecoder().decode(NetworkEnvelope.self, from: data)
        } catch {
            Self.logger.error("Ошибка декодирования конверта: \(error.localizedDescription)")
            return
        }
        
        // Маршрутизация по типу сообщения
        switch envelope.type {
        case .matchmakingResponse:
            await handleMatchmakingResponse(envelope)
            
        case .roomJoined:
            await handleRoomJoined(envelope)
            
        case .move:
            await handleMoveMessage(envelope)
            
        case .gameStateSync:
            await handleGameStateSync(envelope)
            
        case .playerDisconnected:
            await handlePlayerDisconnected(envelope)
            
        case .pong:
            // Heartbeat-ответ — соединение живо
            Self.logger.debug("Pong получен")
            
        case .error:
            await handleServerError(envelope)
            
        case .matchmakingRequest, .joinRoom, .ping:
            // Клиентские сообщения — не должны приходить от сервера
            Self.logger.warning("Получено клиентское сообщение от сервера: \(envelope.type.rawValue)")
        }
    }
    
    // ─────────────────────────────────────────────────────────────
    // MARK: - Обработчики конкретных типов сообщений
    // ─────────────────────────────────────────────────────────────
    
    private func handleMatchmakingResponse(_ envelope: NetworkEnvelope) async {
        do {
            let response = try envelope.decode(MatchmakingResponse.self)
            Self.logger.info("Матч найден! Комната: \(response.roomId), сторона: \(response.assignedPlayer.rawValue)")
            
            // Отменяем таймер матчмейкинга
            await state.setMatchmakingTimer(nil)
            await state.setCurrentRoom(response.roomId)
            await updateConnectionState(.inRoom(roomId: response.roomId))
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.networkService(
                    self,
                    didMatchWith: response.opponentName,
                    roomId: response.roomId,
                    assignedPlayer: response.assignedPlayer
                )
            }
        } catch {
            Self.logger.error("Ошибка разбора MatchmakingResponse: \(error.localizedDescription)")
        }
    }
    
    private func handleRoomJoined(_ envelope: NetworkEnvelope) async {
        do {
            let response = try envelope.decode(RoomJoinedResponse.self)
            Self.logger.info("Присоединились к комнате: \(response.roomId)")
            
            await state.setCurrentRoom(response.roomId)
            await updateConnectionState(.inRoom(roomId: response.roomId))
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.networkService(
                    self,
                    didMatchWith: response.opponentName ?? "Ожидание соперника...",
                    roomId: response.roomId,
                    assignedPlayer: response.assignedPlayer
                )
            }
        } catch {
            Self.logger.error("Ошибка разбора RoomJoinedResponse: \(error.localizedDescription)")
        }
    }
    
    private func handleMoveMessage(_ envelope: NetworkEnvelope) async {
        do {
            let move = try envelope.decode(MoveMessage.self)
            Self.logger.info("Получен ход: \(move.player.rawValue) → клетка \(move.cellIndex)")
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.networkService(self, didReceiveMove: move)
            }
        } catch {
            Self.logger.error("Ошибка разбора MoveMessage: \(error.localizedDescription)")
        }
    }
    
    private func handleGameStateSync(_ envelope: NetworkEnvelope) async {
        do {
            let sync = try envelope.decode(GameStateSync.self)
            Self.logger.info("Синхронизация состояния комнаты: \(sync.roomId)")
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.networkService(self, didReceiveSync: sync)
            }
        } catch {
            Self.logger.error("Ошибка разбора GameStateSync: \(error.localizedDescription)")
        }
    }
    
    private func handlePlayerDisconnected(_ envelope: NetworkEnvelope) async {
        do {
            let msg = try envelope.decode(PlayerDisconnectedMessage.self)
            Self.logger.warning("Соперник \(msg.disconnectedPlayer.rawValue) отключился из комнаты \(msg.roomId)")
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.networkService(self, opponentDisconnectedInRoom: msg.roomId)
            }
        } catch {
            Self.logger.error("Ошибка разбора PlayerDisconnectedMessage: \(error.localizedDescription)")
        }
    }
    
    private func handleServerError(_ envelope: NetworkEnvelope) async {
        do {
            let serverErr = try envelope.decode(ServerErrorMessage.self)
            Self.logger.error("Ошибка сервера [\(serverErr.code)]: \(serverErr.message)")
            
            await notifyError(.serverError(code: serverErr.code, message: serverErr.message))
        } catch {
            Self.logger.error("Ошибка разбора ServerErrorMessage: \(error.localizedDescription)")
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Отправка сообщений
    // ═══════════════════════════════════════════════════════════════
    
    /// Отправляет типизированное сообщение через WebSocket
    private func send<T: Encodable>(type: MessageType, content: T) async {
        guard let wsTask = await state.getWebSocket() else {
            Self.logger.warning("Попытка отправки без активного WebSocket")
            return
        }
        
        do {
            let envelope = try NetworkEnvelope(type: type, content: content)
            let data = try JSONEncoder().encode(envelope)
            
            guard let jsonString = String(data: data, encoding: .utf8) else {
                Self.logger.error("Не удалось конвертировать данные в UTF-8 строку")
                return
            }
            
            try await wsTask.send(.string(jsonString))
            Self.logger.debug("Отправлено сообщение: \(type.rawValue)")
        } catch {
            Self.logger.error("Ошибка отправки [\(type.rawValue)]: \(error.localizedDescription)")
            await handleDisconnection(error: error)
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Heartbeat (Ping/Pong)
    // ═══════════════════════════════════════════════════════════════
    
    /// Запускает периодический ping для обнаружения разрыва соединения.
    /// Если ping не получает pong — инициируется переподключение.
    private func startHeartbeat() async {
        let task = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.config.heartbeatInterval))
                } catch {
                    break // Task отменена
                }
                
                guard !Task.isCancelled else { break }
                
                guard let wsTask = await self.state.getWebSocket() else {
                    break
                }
                
                do {
                    try await wsTask.sendPing()
                    Self.logger.debug("Heartbeat ping отправлен")
                } catch {
                    // Ping не прошёл — соединение мертво
                    Self.logger.warning("Heartbeat ping не прошёл: \(error.localizedDescription)")
                    if !Task.isCancelled {
                        await self.handleDisconnection(error: error)
                    }
                    break
                }
            }
        }
        
        await state.setHeartbeatTask(task)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Таймер матчмейкинга (15 секунд)
    // ═══════════════════════════════════════════════════════════════
    
    /// Запускает таймер ожидания соперника.
    /// По истечении timeout вызывает `networkServiceMatchmakingTimedOut`
    /// для переключения на локального Minimax-бота.
    private func startMatchmakingTimer() async {
        let timeout = config.matchmakingTimeout
        
        let task = Task { [weak self] in
            guard let self else { return }
            
            Self.logger.info("Таймер матчмейкинга запущен: \(timeout)с")
            
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                // Таймер отменён (соперник найден или пользователь отключился)
                Self.logger.info("Таймер матчмейкинга отменён")
                return
            }
            
            // Таймаут истёк — соперник не найден
            guard !Task.isCancelled else { return }
            
            let currentState = await self.state.getConnectionState()
            guard currentState == .matchmaking else { return }
            
            Self.logger.warning("Таймаут матчмейкинга (\(timeout)с). Переключение на локального ИИ.")
            
            // Отключаемся от сервера
            await self.disconnect()
            
            // Уведомляем делегата
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.networkServiceMatchmakingTimedOut(self)
            }
        }
        
        await state.setMatchmakingTimer(task)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Обработка разрыва соединения и переподключение
    // ═══════════════════════════════════════════════════════════════
    //
    // Стратегия Exponential Backoff:
    //   Попытка 1: задержка 1с
    //   Попытка 2: задержка 2с
    //   Попытка 3: задержка 4с
    //   Попытка 4: задержка 8с
    //   Попытка 5: задержка 16с
    //   Все попытки исчерпаны → fallback на ИИ
    //
    // ═══════════════════════════════════════════════════════════════
    
    private func handleDisconnection(error: Error) async {
        // Игнорируем, если отключение было намеренным
        let intentional = await state.isIntentionalDisconnect()
        guard !intentional else { return }
        
        // Останавливаем текущие задачи приёма и heartbeat
        await state.setReceiveTask(nil)
        await state.setHeartbeatTask(nil)
        
        // Закрываем текущий сокет
        if let wsTask = await state.getWebSocket() {
            wsTask.cancel(with: .abnormalClosure, reason: nil)
        }
        
        let attempt = await state.incrementReconnect()
        
        if attempt > config.maxReconnectAttempts {
            // Все попытки исчерпаны
            Self.logger.error("Все \(self.config.maxReconnectAttempts) попыток переподключения исчерпаны")
            await state.teardown()
            await updateConnectionState(.failed(reason: "Переподключение невозможно"))
            await notifyError(.reconnectionExhausted)
            return
        }
        
        // Exponential Backoff: baseDelay * 2^(attempt-1)
        let delay = config.baseReconnectDelay * pow(2.0, Double(attempt - 1))
        
        Self.logger.info("Переподключение: попытка \(attempt)/\(self.config.maxReconnectAttempts), задержка \(delay)с")
        await updateConnectionState(.reconnecting(attempt: attempt))
        
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return // Отменено
        }
        
        // Переподключаемся
        Self.logger.info("Попытка переподключения #\(attempt)...")
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.waitsForConnectivity = true
        
        let session = URLSession(configuration: sessionConfig)
        let wsTask = session.webSocketTask(with: config.serverURL)
        
        await state.setWebSocket(wsTask, session: session, url: config.serverURL)
        wsTask.resume()
        
        // Проверяем успешность через ping
        do {
            try await wsTask.sendPing()
            Self.logger.info("Переподключение успешно (попытка #\(attempt))")
            await state.resetReconnect()
            await updateConnectionState(.connected)
            await startReceiving()
            await startHeartbeat()
            
            // Если была активная комната — запрашиваем синхронизацию
            if let roomId = await state.getCurrentRoom() {
                let joinRequest = JoinRoomRequest(
                    playerId: playerId,
                    roomId: roomId,
                    displayName: displayName
                )
                await send(type: .joinRoom, content: joinRequest)
            }
        } catch {
            // Эта попытка тоже не удалась — рекурсивный вызов
            Self.logger.warning("Попытка переподключения #\(attempt) не удалась: \(error.localizedDescription)")
            await handleDisconnection(error: error)
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Вспомогательные методы
    // ═══════════════════════════════════════════════════════════════
    
    /// Обновляет состояние соединения и уведомляет делегата
    private func updateConnectionState(_ newState: ConnectionState) async {
        await state.setConnectionState(newState)
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.delegate?.networkService(self, didChangeState: newState)
        }
    }
    
    /// Уведомляет делегата об ошибке
    private func notifyError(_ error: NetworkGameServiceError) async {
        Self.logger.error("\(error.description)")
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.delegate?.networkService(self, didFailWithError: error)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - URLSessionWebSocketTask Extension (Async Ping)
// ═══════════════════════════════════════════════════════════════════

extension URLSessionWebSocketTask {
    /// Обёртка для sendPing с async/await (стандартный API использует completion handler)
    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
