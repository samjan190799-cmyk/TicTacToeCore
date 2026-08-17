import XCTest
@testable import TicTacToeCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты PlayerProfile
// ═══════════════════════════════════════════════════════════════════

final class PlayerProfileTests: XCTestCase {
    
    // MARK: - Инициализация
    
    func testDefaultProfileCreation() {
        let profile = PlayerProfile()
        
        XCTAssertEqual(profile.displayName, "Гость")
        XCTAssertEqual(profile.authType, .guest)
        XCTAssertNil(profile.appleUserId)
        XCTAssertNil(profile.gameCenterPlayerId)
        XCTAssertEqual(profile.mmr, PlayerProfile.initialMmr)
        XCTAssertEqual(profile.peakMmr, PlayerProfile.initialMmr)
        XCTAssertEqual(profile.stats.totalGames, 0)
        XCTAssertEqual(profile.stats.wins, 0)
        XCTAssertEqual(profile.stats.losses, 0)
        XCTAssertEqual(profile.stats.draws, 0)
        XCTAssertEqual(profile.stats.currentWinStreak, 0)
        XCTAssertEqual(profile.stats.longestWinStreak, 0)
    }
    
    func testCustomProfileCreation() {
        let profile = PlayerProfile(
            displayName: "Тестер",
            authType: .apple,
            appleUserId: "apple-123",
            mmr: 1500,
            peakMmr: 1800
        )
        
        XCTAssertEqual(profile.displayName, "Тестер")
        XCTAssertEqual(profile.authType, .apple)
        XCTAssertEqual(profile.appleUserId, "apple-123")
        XCTAssertEqual(profile.mmr, 1500)
        XCTAssertEqual(profile.peakMmr, 1800)
    }
    
    // MARK: - MMR обновление
    
    func testApplyWinIncreasesMmr() {
        var profile = PlayerProfile()
        let initialMmr = profile.mmr
        
        profile.applyMatchResult(.win)
        
        XCTAssertEqual(profile.mmr, initialMmr + PlayerProfile.winMmrDelta)
        XCTAssertEqual(profile.stats.wins, 1)
        XCTAssertEqual(profile.stats.totalGames, 1)
        XCTAssertEqual(profile.stats.currentWinStreak, 1)
        XCTAssertEqual(profile.stats.longestWinStreak, 1)
    }
    
    func testApplyLossDecreasesMmr() {
        var profile = PlayerProfile()
        let initialMmr = profile.mmr
        
        profile.applyMatchResult(.loss)
        
        XCTAssertEqual(profile.mmr, initialMmr - PlayerProfile.lossMmrDelta)
        XCTAssertEqual(profile.stats.losses, 1)
        XCTAssertEqual(profile.stats.totalGames, 1)
        XCTAssertEqual(profile.stats.currentWinStreak, 0)
    }
    
    func testApplyDrawIncreasesSlightly() {
        var profile = PlayerProfile()
        let initialMmr = profile.mmr
        
        profile.applyMatchResult(.draw)
        
        XCTAssertEqual(profile.mmr, initialMmr + PlayerProfile.drawMmrDelta)
        XCTAssertEqual(profile.stats.draws, 1)
        XCTAssertEqual(profile.stats.totalGames, 1)
        // Серия побед НЕ прерывается при ничьей
        XCTAssertEqual(profile.stats.currentWinStreak, 0)
    }
    
    func testMmrNeverGoesBelowZero() {
        var profile = PlayerProfile(mmr: 5, peakMmr: 5)
        
        profile.applyMatchResult(.loss) // -20, но не ниже 0
        
        XCTAssertEqual(profile.mmr, PlayerProfile.minMmr)
        XCTAssertTrue(profile.mmr >= 0, "MMR не должен быть отрицательным")
    }
    
    func testMmrNeverExceedsMax() {
        var profile = PlayerProfile(mmr: 2995, peakMmr: 2995)
        
        profile.applyMatchResult(.win) // +25, но не выше 3000
        
        XCTAssertEqual(profile.mmr, PlayerProfile.maxMmr)
    }
    
    func testPeakMmrUpdatesOnNewHigh() {
        var profile = PlayerProfile(mmr: 1000, peakMmr: 1000)
        
        profile.applyMatchResult(.win) // 1000 + 25 = 1025
        XCTAssertEqual(profile.peakMmr, 1025)
        
        profile.applyMatchResult(.loss) // 1025 - 20 = 1005
        XCTAssertEqual(profile.peakMmr, 1025, "Peak MMR не должен уменьшаться")
    }
    
    // MARK: - Серии побед
    
    func testWinStreakTracking() {
        var profile = PlayerProfile()
        
        profile.applyMatchResult(.win) // Серия: 1
        profile.applyMatchResult(.win) // Серия: 2
        profile.applyMatchResult(.win) // Серия: 3
        XCTAssertEqual(profile.stats.currentWinStreak, 3)
        XCTAssertEqual(profile.stats.longestWinStreak, 3)
        
        profile.applyMatchResult(.loss) // Серия сбрасывается
        XCTAssertEqual(profile.stats.currentWinStreak, 0)
        XCTAssertEqual(profile.stats.longestWinStreak, 3, "Лучшая серия сохраняется")
        
        profile.applyMatchResult(.win) // Новая серия: 1
        profile.applyMatchResult(.win) // Новая серия: 2
        XCTAssertEqual(profile.stats.currentWinStreak, 2)
        XCTAssertEqual(profile.stats.longestWinStreak, 3, "Лучшая серия не перезаписывается меньшей")
    }
    
    // MARK: - Win Rate
    
    func testWinRateCalculation() {
        var profile = PlayerProfile()
        
        XCTAssertEqual(profile.winRate, 0.0, "Win rate при 0 играх = 0")
        
        profile.applyMatchResult(.win)
        profile.applyMatchResult(.win)
        profile.applyMatchResult(.loss)
        profile.applyMatchResult(.draw)
        
        XCTAssertEqual(profile.winRate, 0.5, accuracy: 0.01) // 2 победы из 4
    }
    
    // MARK: - Ранговая система
    
    func testRankFromMmr() {
        XCTAssertEqual(PlayerRank.from(mmr: 0), .bronze)
        XCTAssertEqual(PlayerRank.from(mmr: 499), .bronze)
        XCTAssertEqual(PlayerRank.from(mmr: 500), .silver)
        XCTAssertEqual(PlayerRank.from(mmr: 999), .silver)
        XCTAssertEqual(PlayerRank.from(mmr: 1000), .gold)
        XCTAssertEqual(PlayerRank.from(mmr: 1499), .gold)
        XCTAssertEqual(PlayerRank.from(mmr: 1500), .platinum)
        XCTAssertEqual(PlayerRank.from(mmr: 1999), .platinum)
        XCTAssertEqual(PlayerRank.from(mmr: 2000), .diamond)
        XCTAssertEqual(PlayerRank.from(mmr: 2499), .diamond)
        XCTAssertEqual(PlayerRank.from(mmr: 2500), .master)
        XCTAssertEqual(PlayerRank.from(mmr: 3000), .master)
    }
    
    func testProfileRankMatchesMmr() {
        let profile = PlayerProfile(mmr: 1600, peakMmr: 1600)
        XCTAssertEqual(profile.rank, .platinum)
    }
    
    func testRankIconNames() {
        // Убеждаемся, что все ранги имеют непустые иконки
        for rank in PlayerRank.allCases {
            XCTAssertFalse(rank.iconName.isEmpty, "Иконка ранга \(rank.rawValue) не должна быть пустой")
        }
    }
    
    func testRankMinMmrValues() {
        XCTAssertEqual(PlayerRank.bronze.minMmr, 0)
        XCTAssertEqual(PlayerRank.silver.minMmr, 500)
        XCTAssertEqual(PlayerRank.gold.minMmr, 1000)
        XCTAssertEqual(PlayerRank.platinum.minMmr, 1500)
        XCTAssertEqual(PlayerRank.diamond.minMmr, 2000)
        XCTAssertEqual(PlayerRank.master.minMmr, 2500)
    }
    
    // MARK: - Codable Round-Trip
    
    func testProfileCodableRoundTrip() throws {
        var original = PlayerProfile(
            displayName: "Тестер",
            authType: .apple,
            appleUserId: "apple-id-123",
            gameCenterPlayerId: "gc-456",
            mmr: 1750,
            peakMmr: 1800
        )
        original.applyMatchResult(.win)
        original.applyMatchResult(.loss)
        original.applyMatchResult(.draw)
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.authType, original.authType)
        XCTAssertEqual(decoded.appleUserId, original.appleUserId)
        XCTAssertEqual(decoded.gameCenterPlayerId, original.gameCenterPlayerId)
        XCTAssertEqual(decoded.mmr, original.mmr)
        XCTAssertEqual(decoded.peakMmr, original.peakMmr)
        XCTAssertEqual(decoded.stats, original.stats)
    }
    
    func testPlayerStatsCodableRoundTrip() throws {
        let original = PlayerStats(
            totalGames: 42,
            wins: 25,
            losses: 12,
            draws: 5,
            currentWinStreak: 3,
            longestWinStreak: 7
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlayerStats.self, from: data)
        
        XCTAssertEqual(decoded, original)
    }
    
    // MARK: - AuthType
    
    func testAuthTypeCodable() throws {
        let types: [AuthType] = [.guest, .apple, .appleAndGameCenter]
        
        for type in types {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(AuthType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }
    
    // MARK: - MatchResult
    
    func testMatchResultCodable() throws {
        let results: [MatchResult] = [.win, .loss, .draw]
        
        for result in results {
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(MatchResult.self, from: data)
            XCTAssertEqual(decoded, result)
        }
    }
    
    // MARK: - Стресс-тест MMR
    
    func testMmrStressTest() {
        var profile = PlayerProfile()
        
        // 1000 побед подряд — MMR не должен превысить maxMmr
        for _ in 0..<1000 {
            profile.applyMatchResult(.win)
        }
        
        XCTAssertTrue(profile.mmr <= PlayerProfile.maxMmr, "MMR превысил максимум")
        XCTAssertEqual(profile.stats.wins, 1000)
        XCTAssertEqual(profile.stats.totalGames, 1000)
        XCTAssertEqual(profile.stats.currentWinStreak, 1000)
        XCTAssertEqual(profile.stats.longestWinStreak, 1000)
        
        // 2000 поражений подряд — MMR не должен упасть ниже 0
        for _ in 0..<2000 {
            profile.applyMatchResult(.loss)
        }
        
        XCTAssertTrue(profile.mmr >= PlayerProfile.minMmr, "MMR ушёл в минус")
        XCTAssertEqual(profile.stats.totalGames, 3000)
        XCTAssertEqual(profile.stats.currentWinStreak, 0)
        XCTAssertEqual(profile.stats.longestWinStreak, 1000, "Рекорд серии не изменился")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты GameCenterError
// ═══════════════════════════════════════════════════════════════════

final class GameCenterErrorTests: XCTestCase {
    
    func testErrorDescriptions() {
        let errors: [GameCenterError] = [
            .notAuthenticated,
            .authenticationFailed(underlying: "test"),
            .leaderboardNotFound(id: "lb-1"),
            .submitScoreFailed(underlying: "net"),
            .loadScoresFailed(underlying: "timeout"),
            .achievementFailed(underlying: "fail"),
            .gameCenterDisabled
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "Описание ошибки не должно быть пустым")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты LeaderboardEntry
// ═══════════════════════════════════════════════════════════════════

final class LeaderboardEntryTests: XCTestCase {
    
    func testLeaderboardEntryCreation() {
        let entry = LeaderboardEntry(
            id: "player-1",
            rank: 1,
            playerName: "Чемпион",
            score: 2500,
            isLocalPlayer: true
        )
        
        XCTAssertEqual(entry.id, "player-1")
        XCTAssertEqual(entry.rank, 1)
        XCTAssertEqual(entry.playerName, "Чемпион")
        XCTAssertEqual(entry.score, 2500)
        XCTAssertTrue(entry.isLocalPlayer)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты AuthError
// ═══════════════════════════════════════════════════════════════════

final class AuthErrorTests: XCTestCase {
    
    func testAuthErrorDescriptions() {
        let errors: [AuthError] = [
            .appleSignInFailed(underlying: "network"),
            .appleSignInCancelled,
            .credentialRevoked,
            .profileCorrupted,
            .keychainError(.itemNotFound)
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "Описание ошибки не должно быть пустым")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты KeychainError
// ═══════════════════════════════════════════════════════════════════

final class KeychainErrorTests: XCTestCase {
    
    func testKeychainErrorDescriptions() {
        let errors: [KeychainError] = [
            .saveFailed(status: -25299),
            .loadFailed(status: -25300),
            .deleteFailed(status: -25301),
            .dataConversionFailed,
            .itemNotFound
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "Описание ошибки не должно быть пустым")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Тесты LeaderboardID и AchievementID
// ═══════════════════════════════════════════════════════════════════

final class GameCenterIDTests: XCTestCase {
    
    func testLeaderboardIDs() {
        XCTAssertTrue(LeaderboardID.mmrRating.rawValue.contains("mmr"))
        XCTAssertTrue(LeaderboardID.totalWins.rawValue.contains("wins"))
        XCTAssertTrue(LeaderboardID.winStreak.rawValue.contains("streak"))
    }
    
    func testAchievementIDs() {
        // Все ID должны начинаться с reverse-DNS
        let allAchievements: [AchievementID] = [
            .firstWin, .tenWins, .fiftyWins, .hundredWins,
            .flawlessVictory, .winStreak5, .winStreak10,
            .reachGold, .reachPlatinum, .reachDiamond, .reachMaster
        ]
        
        for achievement in allAchievements {
            XCTAssertTrue(
                achievement.rawValue.hasPrefix("com.tictactoe.achievement."),
                "ID достижения должен начинаться с 'com.tictactoe.achievement.'"
            )
        }
        
        XCTAssertEqual(allAchievements.count, 11, "Должно быть 11 достижений")
    }
}
