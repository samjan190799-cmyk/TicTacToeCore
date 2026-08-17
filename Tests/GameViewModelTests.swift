import XCTest
@testable import TicTacToeCore

@MainActor
final class GameViewModelTests: XCTestCase {
    
    var viewModel: GameViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = GameViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - Тесты инициализации
    func testInitialState() {
        XCTAssertEqual(viewModel.board.count, 9)
        XCTAssertTrue(viewModel.board.allSatisfy { $0.player == nil })
        XCTAssertEqual(viewModel.currentPlayer, .x)
        XCTAssertEqual(viewModel.gameState, .active)
        XCTAssertTrue(viewModel.winningIndices.isEmpty)
        XCTAssertEqual(viewModel.gameMode, .vsPlayer)
        XCTAssertFalse(viewModel.isAIThinking)
    }
    
    // MARK: - Тесты ходов и валидации
    func testMakeMoveSwitchesPlayer() {
        viewModel.makeMove(at: 0)
        XCTAssertEqual(viewModel.board[0].player, .x)
        XCTAssertEqual(viewModel.currentPlayer, .o)
        XCTAssertEqual(viewModel.gameState, .active)
        
        viewModel.makeMove(at: 1)
        XCTAssertEqual(viewModel.board[1].player, .o)
        XCTAssertEqual(viewModel.currentPlayer, .x)
    }
    
    func testCannotMoveToOccupiedCell() {
        viewModel.makeMove(at: 4) // X ходит в центр
        XCTAssertEqual(viewModel.board[4].player, .x)
        XCTAssertEqual(viewModel.currentPlayer, .o)
        
        viewModel.makeMove(at: 4) // O пытается сходить в занятый центр
        XCTAssertEqual(viewModel.board[4].player, .x) // Клетка осталась за X
        XCTAssertEqual(viewModel.currentPlayer, .o) // Ход остался у O
    }
    
    func testCannotMoveAfterGameIsWon() {
        // Симулируем победу X по верхней горизонтали [0, 1, 2]
        viewModel.makeMove(at: 0) // X
        viewModel.makeMove(at: 3) // O
        viewModel.makeMove(at: 1) // X
        viewModel.makeMove(at: 4) // O
        viewModel.makeMove(at: 2) // X побеждает!
        
        XCTAssertEqual(viewModel.gameState, .won(.x))
        XCTAssertEqual(viewModel.winningIndices, Set([0, 1, 2]))
        
        // Попытка хода после окончания игры
        viewModel.makeMove(at: 8)
        XCTAssertNil(viewModel.board[8].player)
    }
    
    // MARK: - Тесты проверки победы
    func testDiagonalWin() {
        // Диагональ [0, 4, 8]
        viewModel.makeMove(at: 0) // X
        viewModel.makeMove(at: 1) // O
        viewModel.makeMove(at: 4) // X
        viewModel.makeMove(at: 2) // O
        viewModel.makeMove(at: 8) // X побеждает!
        
        XCTAssertEqual(viewModel.gameState, .won(.x))
        XCTAssertEqual(viewModel.winningIndices, Set([0, 4, 8]))
    }
    
    func testDrawCondition() {
        // Симуляция ничьей:
        // X O X
        // X X O
        // O X O
        let moves = [0, 1, 2, 4, 3, 5, 7, 6, 8]
        for move in moves {
            viewModel.makeMove(at: move)
        }
        
        XCTAssertEqual(viewModel.gameState, .draw)
        XCTAssertTrue(viewModel.winningIndices.isEmpty)
    }
    
    // MARK: - Тест сброса игры
    func testResetGame() {
        viewModel.makeMove(at: 0)
        viewModel.makeMove(at: 1)
        viewModel.resetGame()
        
        XCTAssertEqual(viewModel.board.count, 9)
        XCTAssertTrue(viewModel.board.allSatisfy { $0.player == nil })
        XCTAssertEqual(viewModel.currentPlayer, .x)
        XCTAssertEqual(viewModel.gameState, .active)
        XCTAssertTrue(viewModel.winningIndices.isEmpty)
        XCTAssertFalse(viewModel.isAIThinking)
    }
    
    // MARK: - Тест смены режима сбрасывает игру
    func testChangingModeResetsGame() {
        viewModel.makeMove(at: 0)
        viewModel.makeMove(at: 1)
        XCTAssertEqual(viewModel.board[0].player, .x)
        
        viewModel.gameMode = .vsAI
        
        // Доска должна быть сброшена
        XCTAssertTrue(viewModel.board.allSatisfy { $0.player == nil })
        XCTAssertEqual(viewModel.currentPlayer, .x)
        XCTAssertEqual(viewModel.gameState, .active)
    }
}

// MARK: - Тесты алгоритма Minimax (TicTacToeAI)
final class TicTacToeAITests: XCTestCase {
    
    /// Создаёт пустую доску 3x3
    private func emptyBoard() -> [Cell] {
        (0..<9).map { index in
            Cell(row: index / 3, col: index % 3, player: nil)
        }
    }
    
    /// Создаёт доску из массива Player? (nil = пусто, .x, .o)
    private func boardFromLayout(_ layout: [Player?]) -> [Cell] {
        layout.enumerated().map { index, player in
            Cell(row: index / 3, col: index % 3, player: player)
        }
    }
    
    // MARK: - ИИ должен побеждать, когда есть выигрышный ход
    func testAITakesWinningMove() {
        // Расклад: O в [0,1], X в [3,4] — O может победить, поставив в [2]
        //  O | O | _
        //  X | X | _
        //  _ | _ | _
        let layout: [Player?] = [.o, .o, nil, .x, .x, nil, nil, nil, nil]
        let board = boardFromLayout(layout)
        
        let bestMove = TicTacToeAI.getBestMove(board: board, aiPlayer: .o)
        XCTAssertEqual(bestMove, 2, "ИИ должен завершить линию [0,1,2] и победить")
    }
    
    // MARK: - ИИ должен блокировать победу противника
    func testAIBlocksOpponentWin() {
        // Расклад: X в [0,1], O в [3] — X вот-вот победит по [0,1,2]
        //  X | X | _
        //  O | _ | _
        //  _ | _ | _
        let layout: [Player?] = [.x, .x, nil, .o, nil, nil, nil, nil, nil]
        let board = boardFromLayout(layout)
        
        let bestMove = TicTacToeAI.getBestMove(board: board, aiPlayer: .o)
        XCTAssertEqual(bestMove, 2, "ИИ должен заблокировать победу X в клетке [2]")
    }
    
    // MARK: - ИИ предпочитает быструю победу
    func testAIPrefersQuickWin() {
        // O может победить за 1 ход (поставив в 6) или позже
        //  O | X | _
        //  X | O | _
        //  _ | _ | _
        let layout: [Player?] = [.o, .x, nil, .x, .o, nil, nil, nil, nil]
        let board = boardFromLayout(layout)
        
        let bestMove = TicTacToeAI.getBestMove(board: board, aiPlayer: .o)
        // ИИ должен поставить в [8] — диагональ [0,4,8]
        XCTAssertEqual(bestMove, 8, "ИИ должен выбрать быструю победу по диагонали [0,4,8]")
    }
    
    // MARK: - На пустой доске ИИ возвращает валидный ход
    func testAIReturnsValidMoveOnEmptyBoard() {
        let board = emptyBoard()
        let bestMove = TicTacToeAI.getBestMove(board: board, aiPlayer: .o)
        
        XCTAssertNotNil(bestMove, "ИИ должен вернуть ход на пустой доске")
        XCTAssertTrue((0..<9).contains(bestMove!), "Индекс хода должен быть в диапазоне [0...8]")
    }
    
    // MARK: - На полной доске ИИ возвращает nil
    func testAIReturnsNilOnFullBoard() {
        let layout: [Player?] = [.x, .o, .x, .x, .x, .o, .o, .x, .o]
        let board = boardFromLayout(layout)
        
        let bestMove = TicTacToeAI.getBestMove(board: board, aiPlayer: .o)
        XCTAssertNil(bestMove, "ИИ должен вернуть nil, когда все клетки заняты")
    }
    
    // MARK: - Идеальная игра ИИ: не проигрывает никогда
    func testAINeverLoses() {
        // Прогоняем все 9 возможных первых ходов X,
        // после чего ИИ (O) отвечает идеально — не должно быть побед X
        for firstMove in 0..<9 {
            var board = emptyBoard()
            board[firstMove].player = .x
            
            // Симулируем всю игру: O ходит Minimax, X ходит по первому свободному
            var currentPlayer: Player = .o
            while true {
                let availableMoves = board.indices.filter { board[$0].player == nil }
                if availableMoves.isEmpty { break }
                
                if currentPlayer == .o {
                    // Ход ИИ
                    guard let aiMove = TicTacToeAI.getBestMove(board: board, aiPlayer: .o) else {
                        break
                    }
                    board[aiMove].player = .o
                } else {
                    // Ход X — первый свободный (наивная стратегия)
                    board[availableMoves[0]].player = .x
                }
                
                // Проверяем победу
                if hasWinner(board: board, player: .x) {
                    XCTFail("ИИ проиграл при первом ходе X = \(firstMove). Minimax не должен проигрывать.")
                    return
                }
                if hasWinner(board: board, player: .o) {
                    break // ИИ победил — ок
                }
                
                currentPlayer = currentPlayer.next
            }
        }
    }
    
    // MARK: - Вспомогательный метод проверки победы
    private func hasWinner(board: [Cell], player: Player) -> Bool {
        let patterns: [[Int]] = [
            [0, 1, 2], [3, 4, 5], [6, 7, 8],
            [0, 3, 6], [1, 4, 7], [2, 5, 8],
            [0, 4, 8], [2, 4, 6]
        ]
        return patterns.contains { pattern in
            pattern.allSatisfy { board[$0].player == player }
        }
    }
}
