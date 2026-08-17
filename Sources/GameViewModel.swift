import SwiftUI
import Combine

// MARK: - GameViewModel
/// ViewModel для управления состоянием и логикой игры "Крестики-Нолики"
/// Поддерживает два режима: игрок vs игрок и игрок vs ИИ (Minimax)
@MainActor
public final class GameViewModel: ObservableObject {
    
    // MARK: - Опубликованные свойства
    
    /// Массив из 9 клеток игрового поля (3x3)
    @Published public private(set) var board: [Cell] = []
    
    /// Текущий игрок, чей сейчас ход
    @Published public private(set) var currentPlayer: Player = .x
    
    /// Текущее состояние игры (активна, победа, ничья)
    @Published public private(set) var gameState: GameState = .active
    
    /// Индексы клеток победившей линии (для визуальной подсветки)
    @Published public private(set) var winningIndices: Set<Int> = []
    
    /// Режим игры (vs Player / vs AI)
    @Published public var gameMode: GameMode = .vsPlayer {
        didSet {
            // При смене режима сбрасываем игру
            if oldValue != gameMode {
                resetGame()
            }
        }
    }
    
    /// Флаг: ИИ «думает» (блокировка ввода игрока на время задержки)
    @Published public private(set) var isAIThinking: Bool = false
    
    /// Сторона, за которую играет ИИ (всегда O)
    public let aiPlayer: Player = .o
    
    // MARK: - Приватные свойства
    
    /// Задача хода ИИ — хранится для возможности отмены при сбросе
    private var aiMoveTask: Task<Void, Never>?
    
    // MARK: - Константы победных линий
    
    /// 8 победных комбинаций на поле 3x3: 3 горизонтали, 3 вертикали, 2 диагонали
    public static let winningPatterns: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8], // Горизонтальные линии
        [0, 3, 6], [1, 4, 7], [2, 5, 8], // Вертикальные линии
        [0, 4, 8], [2, 4, 6]             // Диагональные линии
    ]
    
    // MARK: - Инициализатор
    
    public init(gameMode: GameMode = .vsPlayer) {
        self.gameMode = gameMode
        resetGame()
    }
    
    // MARK: - Игровые методы
    
    /// Сброс игры и возврат к начальному состоянию
    public func resetGame() {
        // Отменяем задачу хода ИИ, если она активна
        aiMoveTask?.cancel()
        aiMoveTask = nil
        
        board = (0..<9).map { index in
            Cell(row: index / 3, col: index % 3, player: nil)
        }
        currentPlayer = .x
        gameState = .active
        winningIndices = []
        isAIThinking = false
    }
    
    /// Совершение хода игроком по индексу клетки [0...8]
    /// - Parameter index: Индекс ячейки в массиве board
    public func makeMove(at index: Int) {
        // 1. Валидация корректности индекса
        guard board.indices.contains(index) else {
            return
        }
        
        // 2. Валидация: запрет хода, если ИИ думает
        guard !isAIThinking else {
            return
        }
        
        // 3. Валидация: запрет хода, если игра уже завершена или ячейка занята
        guard gameState == .active, board[index].player == nil else {
            return
        }
        
        // 4. Установка хода текущего игрока
        board[index].player = currentPlayer
        
        // 5. Проверка окончания игры (победа или ничья)
        if checkWinner() {
            return
        }
        
        // 6. Переключение хода на следующего игрока
        currentPlayer = currentPlayer.next
        
        // 7. Если режим vs AI и сейчас ход ИИ — запускаем ход бота
        if gameMode == .vsAI && currentPlayer == aiPlayer {
            scheduleAIMove()
        }
    }
    
    /// Проверка условий победы или ничьей
    /// - Returns: true, если игра завершена (победа или ничья), иначе false
    @discardableResult
    public func checkWinner() -> Bool {
        // Проверяем все 8 победных комбинаций
        for pattern in Self.winningPatterns {
            let i0 = pattern[0]
            let i1 = pattern[1]
            let i2 = pattern[2]
            
            if let winner = board[i0].player,
               winner == board[i1].player,
               winner == board[i2].player {
                gameState = .won(winner)
                winningIndices = Set(pattern)
                return true
            }
        }
        
        // Проверяем заполненность всех клеток (ничья)
        let isBoardFull = board.allSatisfy { $0.player != nil }
        if isBoardFull {
            gameState = .draw
            winningIndices = []
            return true
        }
        
        // Игра продолжается
        gameState = .active
        winningIndices = []
        return false
    }
    
    // MARK: - Ход ИИ
    
    /// Запускает асинхронный ход ИИ с искусственной задержкой для плавности
    private func scheduleAIMove() {
        isAIThinking = true
        
        aiMoveTask = Task { [weak self] in
            guard let self else { return }
            
            // Вычисляем лучший ход на фоне (Minimax — чистая функция, без побочных эффектов)
            let currentBoard = self.board
            let bestMoveIndex = TicTacToeAI.getBestMove(
                board: currentBoard,
                aiPlayer: self.aiPlayer
            )
            
            // Искусственная задержка для визуальной плавности
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                // Task отменена (например, пользователь нажал «Новая игра»)
                return
            }
            
            // Проверяем, что задача не отменена и игра всё ещё активна
            guard !Task.isCancelled, self.gameState == .active else {
                self.isAIThinking = false
                return
            }
            
            self.isAIThinking = false
            
            // Выполняем ход ИИ
            if let moveIndex = bestMoveIndex {
                self.performAIMove(at: moveIndex)
            }
        }
    }
    
    /// Выполняет ход ИИ напрямую, минуя валидацию isAIThinking
    /// (т.к. isAIThinking уже снят перед вызовом)
    private func performAIMove(at index: Int) {
        guard board.indices.contains(index),
              gameState == .active,
              board[index].player == nil else {
            return
        }
        
        board[index].player = currentPlayer
        
        if checkWinner() {
            return
        }
        
        currentPlayer = currentPlayer.next
    }
}
