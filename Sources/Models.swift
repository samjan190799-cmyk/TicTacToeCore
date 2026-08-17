import Foundation

// MARK: - Игрок
/// Перечисление игроков в Крестики-Нолики
public enum Player: String, Codable, CaseIterable, Identifiable, Sendable {
    case x = "X"
    case o = "O"
    
    public var id: String { rawValue }
    
    /// Следующий игрок после текущего
    public var next: Player {
        self == .x ? .o : .x
    }
}

// MARK: - Состояние игры
/// Перечисление возможных состояний матча
public enum GameState: Equatable, Sendable {
    case active
    case won(Player)
    case draw
    
    /// Флаг завершения игры
    public var isGameOver: Bool {
        switch self {
        case .active:
            return false
        case .won, .draw:
            return true
        }
    }
    
    /// Текстовое описание текущего состояния
    public var statusDescription: String {
        switch self {
        case .active:
            return "Игра активна"
        case .won(let player):
            return "Победитель: \(player.rawValue)"
        case .draw:
            return "Ничья"
        }
    }
}

// MARK: - Режим игры
/// Перечисление режимов матча
public enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case vsPlayer = "vs Игрок"
    case vsAI = "vs Компьютер"
    case vsOnline = "Онлайн"
    
    public var id: String { rawValue }
}

// MARK: - Клетка игрового поля
/// Структура, представляющая отдельную клетку 3x3
public struct Cell: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let row: Int
    public let col: Int
    public var player: Player?
    
    public init(id: UUID = UUID(), row: Int, col: Int, player: Player? = nil) {
        self.id = id
        self.row = row
        self.col = col
        self.player = player
    }
    
    /// Занята ли клетка
    public var isOccupied: Bool {
        player != nil
    }
}
