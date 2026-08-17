import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Сетевые Codable-структуры для WebSocket-протокола
// ═══════════════════════════════════════════════════════════════════

/// Тип сообщения для маршрутизации на стороне клиента и сервера
public enum MessageType: String, Codable, Sendable {
    case matchmakingRequest  = "matchmaking_request"
    case matchmakingResponse = "matchmaking_response"
    case joinRoom            = "join_room"
    case roomJoined          = "room_joined"
    case move                = "move"
    case gameStateSync       = "game_state_sync"
    case playerDisconnected  = "player_disconnected"
    case ping                = "ping"
    case pong                = "pong"
    case error               = "error"
}

/// Обёртка-конверт для всех WebSocket-сообщений.
/// Позволяет десериализовать тип до разбора payload.
public struct NetworkEnvelope: Codable, Sendable {
    public let type: MessageType
    public let payload: Data
    
    public init<T: Encodable>(type: MessageType, content: T) throws {
        self.type = type
        self.payload = try JSONEncoder().encode(content)
    }
    
    /// Декодирует payload в конкретный тип
    public func decode<T: Decodable>(_ payloadType: T.Type) throws -> T {
        try JSONDecoder().decode(payloadType, from: payload)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Запрос на матчмейкинг
// ─────────────────────────────────────────────────────────────────

/// Запрос на поиск игры («Найти соперника»)
public struct MatchmakingRequest: Codable, Sendable {
    /// Уникальный идентификатор игрока
    public let playerId: String
    /// Желаемое отображаемое имя
    public let displayName: String
    
    public init(playerId: String, displayName: String) {
        self.playerId = playerId
        self.displayName = displayName
    }
}

/// Ответ сервера на матчмейкинг — комната найдена
public struct MatchmakingResponse: Codable, Sendable {
    /// ID созданной/найденной комнаты
    public let roomId: String
    /// Назначенная сторона (X или O)
    public let assignedPlayer: Player
    /// Имя соперника
    public let opponentName: String
    
    public init(roomId: String, assignedPlayer: Player, opponentName: String) {
        self.roomId = roomId
        self.assignedPlayer = assignedPlayer
        self.opponentName = opponentName
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Подключение по коду комнаты
// ─────────────────────────────────────────────────────────────────

/// Запрос на присоединение к комнате по Room ID
public struct JoinRoomRequest: Codable, Sendable {
    public let playerId: String
    public let roomId: String
    public let displayName: String
    
    public init(playerId: String, roomId: String, displayName: String) {
        self.playerId = playerId
        self.roomId = roomId
        self.displayName = displayName
    }
}

/// Ответ сервера: успешное подключение к комнате
public struct RoomJoinedResponse: Codable, Sendable {
    public let roomId: String
    public let assignedPlayer: Player
    public let opponentName: String?
    
    public init(roomId: String, assignedPlayer: Player, opponentName: String?) {
        self.roomId = roomId
        self.assignedPlayer = assignedPlayer
        self.opponentName = opponentName
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Ход игрока
// ─────────────────────────────────────────────────────────────────

/// Сообщение о ходе игрока (отправляется и принимается)
public struct MoveMessage: Codable, Sendable {
    /// ID комнаты
    public let roomId: String
    /// Кто ходит
    public let player: Player
    /// Индекс клетки [0...8]
    public let cellIndex: Int
    /// Временная метка хода (для порядка при рассинхронизации)
    public let timestamp: TimeInterval
    
    public init(roomId: String, player: Player, cellIndex: Int) {
        self.roomId = roomId
        self.player = player
        self.cellIndex = cellIndex
        self.timestamp = Date().timeIntervalSince1970
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Синхронизация состояния
// ─────────────────────────────────────────────────────────────────

/// Полная синхронизация состояния игры (сервер → клиент).
/// Отправляется при переподключении или рассинхронизации.
public struct GameStateSync: Codable, Sendable {
    /// ID комнаты
    public let roomId: String
    /// Массив из 9 элементов: nil = пусто, "X" или "O"
    public let boardState: [Player?]
    /// Чей сейчас ход
    public let currentTurn: Player
    /// Состояние матча (сериализованное)
    public let gameStatus: GameStatusDTO
    
    public init(roomId: String, boardState: [Player?], currentTurn: Player, gameStatus: GameStatusDTO) {
        self.roomId = roomId
        self.boardState = boardState
        self.currentTurn = currentTurn
        self.gameStatus = gameStatus
    }
}

/// DTO для сериализации GameState через Codable
public enum GameStatusDTO: String, Codable, Sendable {
    case active
    case wonX
    case wonO
    case draw
    
    /// Преобразование из доменного GameState
    public init(from gameState: GameState) {
        switch gameState {
        case .active:       self = .active
        case .won(.x):      self = .wonX
        case .won(.o):      self = .wonO
        case .draw:         self = .draw
        }
    }
    
    /// Преобразование в доменный GameState
    public var toGameState: GameState {
        switch self {
        case .active: return .active
        case .wonX:   return .won(.x)
        case .wonO:   return .won(.o)
        case .draw:   return .draw
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Уведомление об отключении соперника
// ─────────────────────────────────────────────────────────────────

/// Уведомление, что соперник покинул игру
public struct PlayerDisconnectedMessage: Codable, Sendable {
    public let roomId: String
    public let disconnectedPlayer: Player
    
    public init(roomId: String, disconnectedPlayer: Player) {
        self.roomId = roomId
        self.disconnectedPlayer = disconnectedPlayer
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Ошибка сервера
// ─────────────────────────────────────────────────────────────────

/// Сообщение об ошибке от сервера
public struct ServerErrorMessage: Codable, Sendable {
    public let code: Int
    public let message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}
