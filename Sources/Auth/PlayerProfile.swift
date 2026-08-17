import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Модель профиля игрока
// ═══════════════════════════════════════════════════════════════════

/// Профиль игрока с аутентификацией, рейтингом MMR и статистикой.
/// Сериализуется в JSON для хранения в UserDefaults / Keychain.
public struct PlayerProfile: Codable, Equatable, Sendable {
    
    // MARK: - Идентификация
    
    /// Уникальный идентификатор профиля (генерируется при первом запуске)
    public let id: UUID
    
    /// Отображаемое имя (гостевое или из Apple ID)
    public var displayName: String
    
    /// Тип аутентификации
    public var authType: AuthType
    
    /// Идентификатор Apple ID (заполняется после Sign in with Apple)
    public var appleUserId: String?
    
    /// Идентификатор Game Center (заполняется после авторизации GC)
    public var gameCenterPlayerId: String?
    
    // MARK: - Рейтинг MMR
    
    /// Matchmaking Rating — рейтинг для подбора соперников.
    /// Начальный рейтинг: 1000. Диапазон: 0...3000.
    public var mmr: Int
    
    /// Пиковый рейтинг (максимум, достигнутый за всё время)
    public var peakMmr: Int
    
    // MARK: - Статистика
    
    /// Общая игровая статистика
    public var stats: PlayerStats
    
    // MARK: - Метаданные
    
    /// Дата создания профиля
    public let createdAt: Date
    
    /// Дата последнего входа
    public var lastLoginAt: Date
    
    // MARK: - Константы
    
    /// Начальный MMR для новых игроков
    public static let initialMmr: Int = 1000
    
    /// Минимально допустимый MMR
    public static let minMmr: Int = 0
    
    /// Максимально допустимый MMR
    public static let maxMmr: Int = 3000
    
    /// Очки MMR за победу (базовое значение)
    public static let winMmrDelta: Int = 25
    
    /// Очки MMR за поражение (базовое значение)
    public static let lossMmrDelta: Int = 20
    
    /// Очки MMR за ничью
    public static let drawMmrDelta: Int = 5
    
    // MARK: - Инициализатор
    
    /// Создаёт новый гостевой профиль
    public init(
        id: UUID = UUID(),
        displayName: String = "Гость",
        authType: AuthType = .guest,
        appleUserId: String? = nil,
        gameCenterPlayerId: String? = nil,
        mmr: Int = PlayerProfile.initialMmr,
        peakMmr: Int = PlayerProfile.initialMmr,
        stats: PlayerStats = PlayerStats(),
        createdAt: Date = Date(),
        lastLoginAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.authType = authType
        self.appleUserId = appleUserId
        self.gameCenterPlayerId = gameCenterPlayerId
        self.mmr = mmr
        self.peakMmr = peakMmr
        self.stats = stats
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
    }
    
    // MARK: - Обновление MMR
    
    /// Обновляет MMR после завершения матча
    /// - Parameter result: Результат матча
    public mutating func applyMatchResult(_ result: MatchResult) {
        let delta: Int
        
        switch result {
        case .win:
            stats.wins += 1
            stats.currentWinStreak += 1
            stats.longestWinStreak = max(stats.longestWinStreak, stats.currentWinStreak)
            delta = Self.winMmrDelta
            
        case .loss:
            stats.losses += 1
            stats.currentWinStreak = 0
            delta = -Self.lossMmrDelta
            
        case .draw:
            stats.draws += 1
            // Серия побед не прерывается при ничьей
            delta = Self.drawMmrDelta
        }
        
        stats.totalGames += 1
        
        // Применяем дельту с ограничением диапазона [0...3000]
        mmr = max(Self.minMmr, min(Self.maxMmr, mmr + delta))
        peakMmr = max(peakMmr, mmr)
    }
    
    /// Процент побед (0.0...1.0)
    public var winRate: Double {
        guard stats.totalGames > 0 else { return 0.0 }
        return Double(stats.wins) / Double(stats.totalGames)
    }
    
    /// Ранг игрока на основе MMR
    public var rank: PlayerRank {
        PlayerRank.from(mmr: mmr)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тип аутентификации
// ═══════════════════════════════════════════════════════════════════

/// Тип привязки аккаунта
public enum AuthType: String, Codable, Equatable, Sendable {
    /// Гостевой профиль (только UUID, без привязки)
    case guest
    /// Авторизован через Sign in with Apple
    case apple
    /// Авторизован через Apple ID + Game Center
    case appleAndGameCenter
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Результат матча
// ═══════════════════════════════════════════════════════════════════

/// Результат завершённого матча для обновления статистики
public enum MatchResult: String, Codable, Sendable {
    case win
    case loss
    case draw
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Статистика игрока
// ═══════════════════════════════════════════════════════════════════

/// Агрегированная статистика побед, поражений и серий
public struct PlayerStats: Codable, Equatable, Sendable {
    public var totalGames: Int
    public var wins: Int
    public var losses: Int
    public var draws: Int
    public var currentWinStreak: Int
    public var longestWinStreak: Int
    
    public init(
        totalGames: Int = 0,
        wins: Int = 0,
        losses: Int = 0,
        draws: Int = 0,
        currentWinStreak: Int = 0,
        longestWinStreak: Int = 0
    ) {
        self.totalGames = totalGames
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.currentWinStreak = currentWinStreak
        self.longestWinStreak = longestWinStreak
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Ранг игрока
// ═══════════════════════════════════════════════════════════════════

/// Ранговая система на основе MMR
public enum PlayerRank: String, Codable, Sendable, CaseIterable {
    case bronze   = "Бронза"
    case silver   = "Серебро"
    case gold     = "Золото"
    case platinum = "Платина"
    case diamond  = "Алмаз"
    case master   = "Мастер"
    
    /// Определяет ранг по текущему MMR
    public static func from(mmr: Int) -> PlayerRank {
        switch mmr {
        case 0..<500:       return .bronze
        case 500..<1000:    return .silver
        case 1000..<1500:   return .gold
        case 1500..<2000:   return .platinum
        case 2000..<2500:   return .diamond
        default:            return .master
        }
    }
    
    /// SF Symbol для отображения ранга
    public var iconName: String {
        switch self {
        case .bronze:   return "shield.fill"
        case .silver:   return "shield.lefthalf.filled"
        case .gold:     return "star.circle.fill"
        case .platinum: return "crown.fill"
        case .diamond:  return "diamond.fill"
        case .master:   return "trophy.fill"
        }
    }
    
    /// Минимальный MMR для данного ранга
    public var minMmr: Int {
        switch self {
        case .bronze:   return 0
        case .silver:   return 500
        case .gold:     return 1000
        case .platinum: return 1500
        case .diamond:  return 2000
        case .master:   return 2500
        }
    }
}
