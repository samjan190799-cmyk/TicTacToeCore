import Foundation
import GameKit
import os.log

// ═══════════════════════════════════════════════════════════════════
// MARK: - GameCenterService
// ═══════════════════════════════════════════════════════════════════
//
// Интеграция с Game Center (GameKit):
// • Авторизация GKLocalPlayer
// • Загрузка и отправка результатов в Leaderboard
// • Разблокировка и отслеживание достижений (Achievements)
//
// Chaos Simulator:
// ─────────────────
// • Game Center может быть отключён пользователем → graceful fallback
// • Сеть может оборвать загрузку лидерборда → обработка ошибок
// • Песочница (Sandbox) может возвращать пустые данные → nil-safe обработка
// • Повторная авторизация GKLocalPlayer → идемпотентность
//
// ═══════════════════════════════════════════════════════════════════

/// Ошибки Game Center
public enum GameCenterError: Error, Sendable, CustomStringConvertible {
    case notAuthenticated
    case authenticationFailed(underlying: String)
    case leaderboardNotFound(id: String)
    case submitScoreFailed(underlying: String)
    case loadScoresFailed(underlying: String)
    case achievementFailed(underlying: String)
    case gameCenterDisabled
    
    public var description: String {
        switch self {
        case .notAuthenticated:
            return "Game Center: игрок не авторизован"
        case .authenticationFailed(let msg):
            return "Game Center: ошибка авторизации — \(msg)"
        case .leaderboardNotFound(let id):
            return "Game Center: лидерборд '\(id)' не найден"
        case .submitScoreFailed(let msg):
            return "Game Center: ошибка отправки результата — \(msg)"
        case .loadScoresFailed(let msg):
            return "Game Center: ошибка загрузки результатов — \(msg)"
        case .achievementFailed(let msg):
            return "Game Center: ошибка достижения — \(msg)"
        case .gameCenterDisabled:
            return "Game Center отключён пользователем"
        }
    }
}

// MARK: - Идентификаторы лидербордов и достижений

/// ID лидербордов (настраиваются в App Store Connect)
public enum LeaderboardID: String, Sendable {
    case mmrRating     = "com.tictactoe.leaderboard.mmr"
    case totalWins     = "com.tictactoe.leaderboard.wins"
    case winStreak     = "com.tictactoe.leaderboard.streak"
}

/// ID достижений (настраиваются в App Store Connect)
public enum AchievementID: String, Sendable {
    case firstWin       = "com.tictactoe.achievement.first_win"
    case tenWins        = "com.tictactoe.achievement.ten_wins"
    case fiftyWins      = "com.tictactoe.achievement.fifty_wins"
    case hundredWins    = "com.tictactoe.achievement.hundred_wins"
    case flawlessVictory = "com.tictactoe.achievement.flawless" // Победа без потерь клетки
    case winStreak5     = "com.tictactoe.achievement.streak_5"
    case winStreak10    = "com.tictactoe.achievement.streak_10"
    case reachGold      = "com.tictactoe.achievement.rank_gold"
    case reachPlatinum  = "com.tictactoe.achievement.rank_platinum"
    case reachDiamond   = "com.tictactoe.achievement.rank_diamond"
    case reachMaster    = "com.tictactoe.achievement.rank_master"
}

/// Запись лидерборда для отображения в UI
public struct LeaderboardEntry: Identifiable, Sendable {
    public let id: String
    public let rank: Int
    public let playerName: String
    public let score: Int
    public let isLocalPlayer: Bool
    
    public init(id: String, rank: Int, playerName: String, score: Int, isLocalPlayer: Bool) {
        self.id = id
        self.rank = rank
        self.playerName = playerName
        self.score = score
        self.isLocalPlayer = isLocalPlayer
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - GameCenterService
// ═══════════════════════════════════════════════════════════════════

@MainActor
public final class GameCenterService: ObservableObject {
    
    // MARK: - Публичные свойства
    
    /// Авторизован ли игрок в Game Center
    @Published public private(set) var isAuthenticated: Bool = false
    
    /// Отображаемое имя в Game Center
    @Published public private(set) var gameCenterDisplayName: String?
    
    /// Player ID из Game Center
    @Published public private(set) var gameCenterPlayerId: String?
    
    /// Загруженные записи лидерборда
    @Published public private(set) var leaderboardEntries: [LeaderboardEntry] = []
    
    /// Идёт ли сейчас загрузка
    @Published public private(set) var isLoading: Bool = false
    
    // MARK: - Приватные
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TicTacToeCore",
        category: "GameCenterService"
    )
    
    /// Ссылка на AuthService для привязки GC Player ID
    private weak var authService: AuthService?
    
    // MARK: - Инициализатор
    
    public init(authService: AuthService? = nil) {
        self.authService = authService
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Авторизация Game Center
    // ═══════════════════════════════════════════════════════════════
    
    /// Запускает авторизацию GKLocalPlayer.
    /// Game Center показывает системный UI при первом входе.
    public func authenticate() async throws {
        let localPlayer = GKLocalPlayer.local
        
        Self.logger.info("Запуск авторизации Game Center...")
        
        // Устанавливаем обработчик аутентификации
        // GKLocalPlayer.local.authenticateHandler вызывается системой
        return try await withCheckedThrowingContinuation { continuation in
            localPlayer.authenticateHandler = { [weak self] viewController, error in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(throwing: GameCenterError.authenticationFailed(underlying: "self deallocated"))
                        return
                    }
                    
                    if let error {
                        self.isAuthenticated = false
                        Self.logger.error("Game Center авторизация ошибка: \(error.localizedDescription)")
                        continuation.resume(throwing: GameCenterError.authenticationFailed(underlying: error.localizedDescription))
                        return
                    }
                    
                    if viewController != nil {
                        // Системный UI для входа — в реальном приложении нужно показать этот VC
                        // Для модульной архитектуры это обрабатывается уровнем выше (View)
                        Self.logger.info("Game Center требует UI для входа")
                        continuation.resume(throwing: GameCenterError.gameCenterDisabled)
                        return
                    }
                    
                    if localPlayer.isAuthenticated {
                        self.isAuthenticated = true
                        self.gameCenterDisplayName = localPlayer.displayName
                        self.gameCenterPlayerId = localPlayer.gamePlayerID
                        
                        // Привязываем GC к профилю
                        self.authService?.linkGameCenter(playerId: localPlayer.gamePlayerID)
                        
                        Self.logger.info("Game Center авторизован: \(localPlayer.displayName)")
                        continuation.resume()
                    } else {
                        self.isAuthenticated = false
                        Self.logger.warning("Game Center: игрок не авторизован")
                        continuation.resume(throwing: GameCenterError.gameCenterDisabled)
                    }
                }
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Лидерборды
    // ═══════════════════════════════════════════════════════════════
    
    /// Отправляет результат в лидерборд
    /// - Parameters:
    ///   - score: Значение (MMR, количество побед и т.д.)
    ///   - leaderboardId: Идентификатор лидерборда
    public func submitScore(_ score: Int, to leaderboardId: LeaderboardID) async throws {
        guard isAuthenticated else {
            throw GameCenterError.notAuthenticated
        }
        
        Self.logger.info("Отправка результата \(score) в лидерборд '\(leaderboardId.rawValue)'")
        
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardId.rawValue]
            )
            Self.logger.info("Результат отправлен успешно")
        } catch {
            Self.logger.error("Ошибка отправки результата: \(error.localizedDescription)")
            throw GameCenterError.submitScoreFailed(underlying: error.localizedDescription)
        }
    }
    
    /// Обновляет все лидерборды на основе профиля игрока
    public func syncLeaderboards(with profile: PlayerProfile) async {
        guard isAuthenticated else {
            Self.logger.debug("Game Center не авторизован — пропуск синхронизации лидербордов")
            return
        }
        
        // Отправляем MMR
        try? await submitScore(profile.mmr, to: .mmrRating)
        
        // Отправляем количество побед
        try? await submitScore(profile.stats.wins, to: .totalWins)
        
        // Отправляем лучшую серию побед
        try? await submitScore(profile.stats.longestWinStreak, to: .winStreak)
    }
    
    /// Загружает топ-записи из лидерборда
    /// - Parameters:
    ///   - leaderboardId: Идентификатор лидерборда
    ///   - scope: Область (глобальный / среди друзей)
    ///   - count: Количество записей для загрузки
    public func loadLeaderboard(
        _ leaderboardId: LeaderboardID,
        scope: GKLeaderboard.PlayerScope = .global,
        count: Int = 25
    ) async throws {
        guard isAuthenticated else {
            throw GameCenterError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        Self.logger.info("Загрузка лидерборда '\(leaderboardId.rawValue)' (top \(count))...")
        
        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(
                IDs: [leaderboardId.rawValue]
            )
            
            guard let leaderboard = leaderboards.first else {
                throw GameCenterError.leaderboardNotFound(id: leaderboardId.rawValue)
            }
            
            let (_, scores, _) = try await leaderboard.loadEntries(
                for: scope,
                timeScope: .allTime,
                range: NSRange(location: 1, length: count)
            )
            
            // Преобразуем GKLeaderboard.Entry в наши LeaderboardEntry
            leaderboardEntries = scores.map { entry in
                LeaderboardEntry(
                    id: entry.player.gamePlayerID,
                    rank: entry.rank,
                    playerName: entry.player.displayName,
                    score: entry.score,
                    isLocalPlayer: entry.player == GKLocalPlayer.local
                )
            }
            
            Self.logger.info("Загружено \(self.leaderboardEntries.count) записей лидерборда")
        } catch let error as GameCenterError {
            throw error
        } catch {
            Self.logger.error("Ошибка загрузки лидерборда: \(error.localizedDescription)")
            throw GameCenterError.loadScoresFailed(underlying: error.localizedDescription)
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Достижения
    // ═══════════════════════════════════════════════════════════════
    
    /// Разблокировать достижение (100% прогресса)
    public func unlockAchievement(_ achievementId: AchievementID) async throws {
        try await reportAchievementProgress(achievementId, percentComplete: 100.0)
    }
    
    /// Обновляет прогресс достижения
    /// - Parameters:
    ///   - achievementId: Идентификатор достижения
    ///   - percentComplete: Процент выполнения (0.0...100.0)
    public func reportAchievementProgress(
        _ achievementId: AchievementID,
        percentComplete: Double
    ) async throws {
        guard isAuthenticated else {
            throw GameCenterError.notAuthenticated
        }
        
        let achievement = GKAchievement(identifier: achievementId.rawValue)
        achievement.percentComplete = min(100.0, max(0.0, percentComplete))
        achievement.showsCompletionBanner = true
        
        Self.logger.info("Обновление достижения '\(achievementId.rawValue)': \(percentComplete)%")
        
        do {
            try await GKAchievement.report([achievement])
            Self.logger.info("Достижение обновлено успешно")
        } catch {
            Self.logger.error("Ошибка обновления достижения: \(error.localizedDescription)")
            throw GameCenterError.achievementFailed(underlying: error.localizedDescription)
        }
    }
    
    /// Проверяет и разблокирует достижения на основе текущего профиля
    public func checkAndUnlockAchievements(for profile: PlayerProfile) async {
        guard isAuthenticated else { return }
        
        let wins = profile.stats.wins
        let streak = profile.stats.longestWinStreak
        let rank = profile.rank
        
        // Достижения по количеству побед
        if wins >= 1   { try? await unlockAchievement(.firstWin) }
        if wins >= 10  { try? await unlockAchievement(.tenWins) }
        if wins >= 50  { try? await unlockAchievement(.fiftyWins) }
        if wins >= 100 { try? await unlockAchievement(.hundredWins) }
        
        // Достижения по серии побед
        if streak >= 5  { try? await unlockAchievement(.winStreak5) }
        if streak >= 10 { try? await unlockAchievement(.winStreak10) }
        
        // Достижения по рангу
        switch rank {
        case .master:
            try? await unlockAchievement(.reachMaster)
            try? await unlockAchievement(.reachDiamond)
            try? await unlockAchievement(.reachPlatinum)
            try? await unlockAchievement(.reachGold)
        case .diamond:
            try? await unlockAchievement(.reachDiamond)
            try? await unlockAchievement(.reachPlatinum)
            try? await unlockAchievement(.reachGold)
        case .platinum:
            try? await unlockAchievement(.reachPlatinum)
            try? await unlockAchievement(.reachGold)
        case .gold:
            try? await unlockAchievement(.reachGold)
        case .bronze, .silver:
            break
        }
    }
    
    /// Открывает системный Game Center Dashboard
    public func showGameCenterDashboard() {
        guard isAuthenticated else {
            Self.logger.warning("Game Center не авторизован — невозможно показать Dashboard")
            return
        }
        
        #if canImport(UIKit)
        let gcViewController = GKGameCenterViewController(state: .default)
        
        // Получаем topmost ViewController для презентации
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(gcViewController, animated: true)
        }
        #endif
    }
}
