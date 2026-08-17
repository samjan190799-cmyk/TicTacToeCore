import Foundation

// MARK: - TicTacToeAI
/// Интеллектуальный противник с непобедимым алгоритмом Minimax.
///
/// Minimax рекурсивно перебирает все возможные будущие состояния доски,
/// оценивая терминальные позиции:
/// - Победа ИИ: +10
/// - Победа человека: −10
/// - Ничья: 0
///
/// Глубина вычитается из оценки, чтобы ИИ предпочитал быструю победу
/// и затягивал проигрыш как можно дольше.
public struct TicTacToeAI: Sendable {
    
    /// Задержка хода бота для визуальной плавности (секунды)
    public static let moveDelay: TimeInterval = 0.4
    
    // MARK: - Публичный API
    
    /// Вычисляет оптимальный ход для указанного игрока-ИИ.
    /// - Parameters:
    ///   - board: Текущее состояние игрового поля (массив из 9 клеток)
    ///   - aiPlayer: Сторона, за которую играет ИИ (.x или .o)
    /// - Returns: Индекс лучшей клетки [0...8], или nil если ходов нет
    public static func getBestMove(board: [Cell], aiPlayer: Player) -> Int? {
        // Собираем индексы свободных клеток
        let availableMoves = board.indices.filter { board[$0].player == nil }
        
        // Нет доступных ходов — возвращаем nil
        guard !availableMoves.isEmpty else {
            return nil
        }
        
        var bestScore = Int.min
        var bestIndex: Int? = nil
        
        for index in availableMoves {
            // Симулируем ход ИИ
            var simulatedBoard = board
            simulatedBoard[index].player = aiPlayer
            
            // Рекурсивно оцениваем позицию (следующий ход — за противником)
            let score = minimax(
                board: simulatedBoard,
                depth: 0,
                isMaximizing: false,
                aiPlayer: aiPlayer
            )
            
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        
        return bestIndex
    }
    
    // MARK: - Алгоритм Minimax
    
    /// Рекурсивная оценка позиции методом Minimax.
    /// - Parameters:
    ///   - board: Текущее состояние поля
    ///   - depth: Глубина рекурсии (для предпочтения быстрых побед)
    ///   - isMaximizing: true — ход ИИ (максимизация), false — ход противника (минимизация)
    ///   - aiPlayer: Сторона ИИ
    /// - Returns: Числовая оценка позиции
    private static func minimax(
        board: [Cell],
        depth: Int,
        isMaximizing: Bool,
        aiPlayer: Player
    ) -> Int {
        let humanPlayer = aiPlayer.next
        
        // --- Проверка терминального состояния ---
        
        // Победа ИИ: +10 с бонусом за скорость (чем меньше depth, тем лучше)
        if checkWin(board: board, player: aiPlayer) {
            return 10 - depth
        }
        
        // Победа человека: −10 с учётом глубины (затягиваем проигрыш)
        if checkWin(board: board, player: humanPlayer) {
            return depth - 10
        }
        
        // Ничья (все клетки заняты, нет победителя)
        let availableMoves = board.indices.filter { board[$0].player == nil }
        if availableMoves.isEmpty {
            return 0
        }
        
        // --- Рекурсивный перебор ---
        
        if isMaximizing {
            // Ход ИИ — ищем максимальную оценку
            var bestScore = Int.min
            for index in availableMoves {
                var simulatedBoard = board
                simulatedBoard[index].player = aiPlayer
                let score = minimax(
                    board: simulatedBoard,
                    depth: depth + 1,
                    isMaximizing: false,
                    aiPlayer: aiPlayer
                )
                bestScore = max(bestScore, score)
            }
            return bestScore
        } else {
            // Ход человека — ищем минимальную оценку
            var bestScore = Int.max
            for index in availableMoves {
                var simulatedBoard = board
                simulatedBoard[index].player = humanPlayer
                let score = minimax(
                    board: simulatedBoard,
                    depth: depth + 1,
                    isMaximizing: true,
                    aiPlayer: aiPlayer
                )
                bestScore = min(bestScore, score)
            }
            return bestScore
        }
    }
    
    // MARK: - Проверка победы для симуляции
    
    /// Проверяет, есть ли выигрышная комбинация у указанного игрока.
    /// Использует те же паттерны, что и GameViewModel.
    /// - Parameters:
    ///   - board: Состояние поля
    ///   - player: Проверяемый игрок
    /// - Returns: true, если игрок занял полную линию
    private static func checkWin(board: [Cell], player: Player) -> Bool {
        for pattern in GameViewModel.winningPatterns {
            let i0 = pattern[0]
            let i1 = pattern[1]
            let i2 = pattern[2]
            
            if board[i0].player == player,
               board[i1].player == player,
               board[i2].player == player {
                return true
            }
        }
        return false
    }
}
