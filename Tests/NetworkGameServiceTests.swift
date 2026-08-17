import XCTest
@testable import TicTacToeCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты сетевых моделей (Codable)
// ═══════════════════════════════════════════════════════════════════

final class NetworkModelsTests: XCTestCase {
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - MoveMessage
    
    func testMoveMessageCodable() throws {
        let original = MoveMessage(roomId: "room-123", player: .x, cellIndex: 4)
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MoveMessage.self, from: data)
        
        XCTAssertEqual(decoded.roomId, "room-123")
        XCTAssertEqual(decoded.player, .x)
        XCTAssertEqual(decoded.cellIndex, 4)
        XCTAssertTrue(decoded.timestamp > 0)
    }
    
    // MARK: - MatchmakingRequest
    
    func testMatchmakingRequestCodable() throws {
        let request = MatchmakingRequest(playerId: "player-1", displayName: "Тестер")
        
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(MatchmakingRequest.self, from: data)
        
        XCTAssertEqual(decoded.playerId, "player-1")
        XCTAssertEqual(decoded.displayName, "Тестер")
    }
    
    // MARK: - MatchmakingResponse
    
    func testMatchmakingResponseCodable() throws {
        let response = MatchmakingResponse(
            roomId: "room-abc",
            assignedPlayer: .o,
            opponentName: "Соперник"
        )
        
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(MatchmakingResponse.self, from: data)
        
        XCTAssertEqual(decoded.roomId, "room-abc")
        XCTAssertEqual(decoded.assignedPlayer, .o)
        XCTAssertEqual(decoded.opponentName, "Соперник")
    }
    
    // MARK: - JoinRoomRequest
    
    func testJoinRoomRequestCodable() throws {
        let request = JoinRoomRequest(
            playerId: "p-42",
            roomId: "rm-999",
            displayName: "Игрок"
        )
        
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(JoinRoomRequest.self, from: data)
        
        XCTAssertEqual(decoded.playerId, "p-42")
        XCTAssertEqual(decoded.roomId, "rm-999")
        XCTAssertEqual(decoded.displayName, "Игрок")
    }
    
    // MARK: - GameStateSync
    
    func testGameStateSyncCodable() throws {
        let boardState: [Player?] = [.x, nil, .o, nil, .x, nil, nil, nil, .o]
        let sync = GameStateSync(
            roomId: "room-sync",
            boardState: boardState,
            currentTurn: .x,
            gameStatus: .active
        )
        
        let data = try encoder.encode(sync)
        let decoded = try decoder.decode(GameStateSync.self, from: data)
        
        XCTAssertEqual(decoded.roomId, "room-sync")
        XCTAssertEqual(decoded.boardState.count, 9)
        XCTAssertEqual(decoded.boardState[0], .x)
        XCTAssertNil(decoded.boardState[1])
        XCTAssertEqual(decoded.boardState[2], .o)
        XCTAssertEqual(decoded.currentTurn, .x)
        XCTAssertEqual(decoded.gameStatus, .active)
    }
    
    // MARK: - GameStatusDTO
    
    func testGameStatusDTORoundTrip() {
        // Проверяем все варианты конвертации GameState ↔ GameStatusDTO
        let states: [GameState] = [.active, .won(.x), .won(.o), .draw]
        
        for originalState in states {
            let dto = GameStatusDTO(from: originalState)
            let restored = dto.toGameState
            XCTAssertEqual(restored, originalState, "Round-trip не совпал для \(originalState)")
        }
    }
    
    func testGameStatusDTOCodable() throws {
        let allDTOs: [GameStatusDTO] = [.active, .wonX, .wonO, .draw]
        
        for dto in allDTOs {
            let data = try encoder.encode(dto)
            let decoded = try decoder.decode(GameStatusDTO.self, from: data)
            XCTAssertEqual(decoded, dto)
        }
    }
    
    // MARK: - NetworkEnvelope
    
    func testNetworkEnvelopeEncodeAndDecode() throws {
        let move = MoveMessage(roomId: "r-1", player: .x, cellIndex: 0)
        let envelope = try NetworkEnvelope(type: .move, content: move)
        
        XCTAssertEqual(envelope.type, .move)
        
        let decodedMove = try envelope.decode(MoveMessage.self)
        XCTAssertEqual(decodedMove.roomId, "r-1")
        XCTAssertEqual(decodedMove.player, .x)
        XCTAssertEqual(decodedMove.cellIndex, 0)
    }
    
    func testNetworkEnvelopeFullRoundTrip() throws {
        // Полный цикл: создание → JSON → декодирование → извлечение payload
        let request = MatchmakingRequest(playerId: "p-1", displayName: "Тест")
        let originalEnvelope = try NetworkEnvelope(type: .matchmakingRequest, content: request)
        
        let jsonData = try encoder.encode(originalEnvelope)
        let restoredEnvelope = try decoder.decode(NetworkEnvelope.self, from: jsonData)
        
        XCTAssertEqual(restoredEnvelope.type, .matchmakingRequest)
        
        let restoredRequest = try restoredEnvelope.decode(MatchmakingRequest.self)
        XCTAssertEqual(restoredRequest.playerId, "p-1")
        XCTAssertEqual(restoredRequest.displayName, "Тест")
    }
    
    // MARK: - PlayerDisconnectedMessage
    
    func testPlayerDisconnectedCodable() throws {
        let msg = PlayerDisconnectedMessage(roomId: "r-dc", disconnectedPlayer: .o)
        
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(PlayerDisconnectedMessage.self, from: data)
        
        XCTAssertEqual(decoded.roomId, "r-dc")
        XCTAssertEqual(decoded.disconnectedPlayer, .o)
    }
    
    // MARK: - ServerErrorMessage
    
    func testServerErrorMessageCodable() throws {
        let err = ServerErrorMessage(code: 404, message: "Комната не найдена")
        
        let data = try encoder.encode(err)
        let decoded = try decoder.decode(ServerErrorMessage.self, from: data)
        
        XCTAssertEqual(decoded.code, 404)
        XCTAssertEqual(decoded.message, "Комната не найдена")
    }
    
    // MARK: - MessageType
    
    func testMessageTypeRawValues() {
        XCTAssertEqual(MessageType.matchmakingRequest.rawValue, "matchmaking_request")
        XCTAssertEqual(MessageType.move.rawValue, "move")
        XCTAssertEqual(MessageType.gameStateSync.rawValue, "game_state_sync")
        XCTAssertEqual(MessageType.playerDisconnected.rawValue, "player_disconnected")
        XCTAssertEqual(MessageType.ping.rawValue, "ping")
        XCTAssertEqual(MessageType.pong.rawValue, "pong")
        XCTAssertEqual(MessageType.error.rawValue, "error")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты NetworkGameService (конфигурация и состояние)
// ═══════════════════════════════════════════════════════════════════

final class NetworkGameServiceTests: XCTestCase {
    
    // MARK: - Инициализация и конфигурация
    
    func testServiceInitialization() async {
        let config = NetworkConfig(
            serverURL: URL(string: "wss://example.com/ws")!,
            matchmakingTimeout: 15.0,
            maxReconnectAttempts: 5,
            baseReconnectDelay: 1.0,
            heartbeatInterval: 10.0
        )
        
        let service = NetworkGameService(
            config: config,
            playerId: "test-player",
            displayName: "Тестовый игрок"
        )
        
        XCTAssertEqual(service.playerId, "test-player")
        XCTAssertEqual(service.displayName, "Тестовый игрок")
        XCTAssertEqual(service.config.matchmakingTimeout, 15.0)
        XCTAssertEqual(service.config.maxReconnectAttempts, 5)
        XCTAssertEqual(service.config.baseReconnectDelay, 1.0)
        XCTAssertEqual(service.config.heartbeatInterval, 10.0)
        
        let state = await service.currentConnectionState()
        XCTAssertEqual(state, .disconnected)
    }
    
    func testDefaultConfigValues() {
        let config = NetworkConfig(serverURL: URL(string: "wss://test.io")!)
        
        XCTAssertEqual(config.matchmakingTimeout, 15.0)
        XCTAssertEqual(config.maxReconnectAttempts, 5)
        XCTAssertEqual(config.baseReconnectDelay, 1.0)
        XCTAssertEqual(config.heartbeatInterval, 10.0)
    }
    
    // MARK: - ConnectionState Equatable
    
    func testConnectionStateEquatable() {
        XCTAssertEqual(ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(ConnectionState.connecting, .connecting)
        XCTAssertEqual(ConnectionState.connected, .connected)
        XCTAssertEqual(ConnectionState.matchmaking, .matchmaking)
        XCTAssertEqual(ConnectionState.inRoom(roomId: "r-1"), .inRoom(roomId: "r-1"))
        XCTAssertNotEqual(ConnectionState.inRoom(roomId: "r-1"), .inRoom(roomId: "r-2"))
        XCTAssertEqual(ConnectionState.reconnecting(attempt: 3), .reconnecting(attempt: 3))
        XCTAssertNotEqual(ConnectionState.reconnecting(attempt: 1), .reconnecting(attempt: 2))
        XCTAssertEqual(ConnectionState.failed(reason: "тест"), .failed(reason: "тест"))
    }
    
    // MARK: - Ошибки сервиса
    
    func testNetworkGameServiceErrorDescriptions() {
        let errors: [NetworkGameServiceError] = [
            .invalidURL,
            .connectionFailed(underlying: "timeout"),
            .encodingFailed(underlying: "bad data"),
            .decodingFailed(underlying: "parse error"),
            .unexpectedMessageType("unknown"),
            .serverError(code: 500, message: "internal"),
            .reconnectionExhausted,
            .alreadyConnected
        ]
        
        for error in errors {
            // Проверяем, что description не пустое
            XCTAssertFalse(error.description.isEmpty, "Описание ошибки не должно быть пустым")
        }
    }
    
    // MARK: - Тест отключения
    
    func testDisconnectSetsStateToDisconnected() async {
        let config = NetworkConfig(serverURL: URL(string: "wss://test.io")!)
        let service = NetworkGameService(config: config, playerId: "p-1", displayName: "Тест")
        
        await service.disconnect()
        
        let state = await service.currentConnectionState()
        XCTAssertEqual(state, .disconnected)
    }
}
