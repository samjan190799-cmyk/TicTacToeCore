import Foundation
import AuthenticationServices
import os.log

// ═══════════════════════════════════════════════════════════════════
// MARK: - AuthService
// ═══════════════════════════════════════════════════════════════════
//
// Сервис аутентификации с двойной стратегией:
//
// 1. ГОСТЕВОЙ РЕЖИМ (по умолчанию):
//    При первом запуске генерируется UUID → создаётся гостевой ProfileProfile.
//    Профиль сохраняется в UserDefaults (статистика) + Keychain (Apple ID).
//
// 2. SIGN IN WITH APPLE (по клику):
//    Пользователь может привязать Apple ID к существующему гостевому профилю.
//    Apple User ID сохраняется в Keychain; при следующем запуске
//    проверяется состояние авторизации через ASAuthorizationAppleIDProvider.
//
// Chaos Simulator:
// ─────────────────
// • Apple может отозвать авторизацию → проверка getCredentialState при запуске
// • Keychain может быть пуст после переустановки → fallback на гостевой профиль
// • UserDefaults может быть очищен → восстановление из Keychain
//
// ═══════════════════════════════════════════════════════════════════

/// Ошибки сервиса аутентификации
public enum AuthError: Error, Sendable, CustomStringConvertible {
    case appleSignInFailed(underlying: String)
    case appleSignInCancelled
    case credentialRevoked
    case profileCorrupted
    case keychainError(KeychainError)
    
    public var description: String {
        switch self {
        case .appleSignInFailed(let msg):
            return "Sign in with Apple не удался: \(msg)"
        case .appleSignInCancelled:
            return "Sign in with Apple отменён пользователем"
        case .credentialRevoked:
            return "Авторизация Apple отозвана"
        case .profileCorrupted:
            return "Профиль повреждён, создан новый"
        case .keychainError(let err):
            return "Ошибка Keychain: \(err.description)"
        }
    }
}

/// Делегат для уведомлений об изменении статуса авторизации
@MainActor
public protocol AuthServiceDelegate: AnyObject {
    /// Профиль загружен или обновлён
    func authService(_ service: AuthService, didUpdateProfile profile: PlayerProfile)
    
    /// Произошла ошибка аутентификации
    func authService(_ service: AuthService, didEncounterError error: AuthError)
    
    /// Авторизация Apple отозвана — профиль понижен до гостевого
    func authServiceDidRevokeAppleAuth(_ service: AuthService)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - AuthService (Основной класс)
// ═══════════════════════════════════════════════════════════════════

@MainActor
public final class AuthService: NSObject, ObservableObject {
    
    // MARK: - Публичные свойства
    
    /// Текущий профиль игрока
    @Published public private(set) var currentProfile: PlayerProfile
    
    /// Идёт ли сейчас процесс авторизации
    @Published public private(set) var isAuthenticating: Bool = false
    
    /// Привязан ли Apple ID
    public var isAppleLinked: Bool {
        currentProfile.authType == .apple || currentProfile.authType == .appleAndGameCenter
    }
    
    // MARK: - Делегат
    
    public weak var delegate: AuthServiceDelegate?
    
    // MARK: - Приватные свойства
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TicTacToeCore",
        category: "AuthService"
    )
    
    /// Ключ UserDefaults для хранения профиля
    private static let profileUserDefaultsKey = "player_profile_data"
    
    /// Continuation для async-обёртки ASAuthorizationController
    private var signInContinuation: CheckedContinuation<ASAuthorization, Error>?
    
    // MARK: - Инициализатор
    
    public override init() {
        // Загружаем существующий профиль или создаём гостевой
        self.currentProfile = Self.loadOrCreateProfile()
        super.init()
        
        Self.logger.info("Профиль загружен: \(self.currentProfile.displayName) [\(self.currentProfile.authType.rawValue)]")
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Загрузка / создание профиля
    // ═══════════════════════════════════════════════════════════════
    
    /// Загружает профиль из UserDefaults, или восстанавливает из Keychain,
    /// или создаёт новый гостевой профиль.
    private static func loadOrCreateProfile() -> PlayerProfile {
        // Стратегия 1: Загрузка из UserDefaults
        if let data = UserDefaults.standard.data(forKey: profileUserDefaultsKey),
           let profile = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            logger.debug("Профиль загружен из UserDefaults")
            return profile
        }
        
        // Стратегия 2: Восстановление из Keychain (после очистки UserDefaults)
        if case .success(let profile) = KeychainHelper.loadObject(PlayerProfile.self, forKey: .playerProfile) {
            logger.info("Профиль восстановлен из Keychain (UserDefaults был очищен)")
            // Записываем обратно в UserDefaults
            saveProfileToUserDefaults(profile)
            return profile
        }
        
        // Стратегия 3: Создание нового гостевого профиля
        let newProfile = PlayerProfile()
        logger.info("Создан новый гостевой профиль: \(newProfile.id.uuidString)")
        saveProfileToUserDefaults(newProfile)
        _ = KeychainHelper.save(object: newProfile, forKey: .playerProfile)
        
        return newProfile
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Sign in with Apple
    // ═══════════════════════════════════════════════════════════════
    
    /// Запускает процесс Sign in with Apple.
    /// Если успешно — привязывает Apple ID к текущему гостевому профилю.
    public func signInWithApple() async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        Self.logger.info("Запуск Sign in with Apple...")
        
        let authorization: ASAuthorization
        
        do {
            authorization = try await performAppleSignIn()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            Self.logger.info("Sign in with Apple отменён пользователем")
            throw AuthError.appleSignInCancelled
        } catch {
            Self.logger.error("Sign in with Apple ошибка: \(error.localizedDescription)")
            throw AuthError.appleSignInFailed(underlying: error.localizedDescription)
        }
        
        // Извлекаем credential
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.appleSignInFailed(underlying: "Некорректный тип credential")
        }
        
        let appleUserId = credential.user
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        
        // Обновляем профиль
        currentProfile.appleUserId = appleUserId
        currentProfile.authType = currentProfile.gameCenterPlayerId != nil
            ? .appleAndGameCenter
            : .apple
        
        // Имя из Apple доступно только при первом входе
        if !fullName.isEmpty {
            currentProfile.displayName = fullName
        }
        
        currentProfile.lastLoginAt = Date()
        
        // Сохраняем Apple User ID в Keychain (отдельно для быстрого доступа)
        _ = KeychainHelper.save(string: appleUserId, forKey: .appleUserId)
        
        // Сохраняем обновлённый профиль
        saveProfile()
        
        Self.logger.info("Apple ID привязан: \(appleUserId.prefix(8))...")
        delegate?.authService(self, didUpdateProfile: currentProfile)
    }
    
    /// Async-обёртка над ASAuthorizationController
    private func performAppleSignIn() async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Проверка состояния Apple ID
    // ═══════════════════════════════════════════════════════════════
    
    /// Проверяет, не отозвана ли авторизация Apple ID.
    /// Вызывается при запуске приложения.
    public func verifyAppleCredentialState() async {
        guard let appleUserId = currentProfile.appleUserId else {
            Self.logger.debug("Apple ID не привязан — проверка не требуется")
            return
        }
        
        Self.logger.info("Проверка состояния Apple ID: \(appleUserId.prefix(8))...")
        
        let provider = ASAuthorizationAppleIDProvider()
        
        do {
            let state = try await provider.credentialState(forUserID: appleUserId)
            
            switch state {
            case .authorized:
                Self.logger.info("Apple ID авторизован ✓")
                
            case .revoked, .notFound:
                Self.logger.warning("Apple ID отозван или не найден — понижение до гостевого")
                revokeAppleAuth()
                
            case .transferred:
                Self.logger.info("Apple ID перенесён (transferred)")
                
            @unknown default:
                Self.logger.warning("Неизвестное состояние Apple credential: \(state.rawValue)")
            }
        } catch {
            // Ошибка проверки (нет сети и т.д.) — не отзываем, ждём следующей проверки
            Self.logger.warning("Ошибка проверки Apple credential (сеть?): \(error.localizedDescription)")
        }
    }
    
    /// Отзыв авторизации Apple — понижение до гостевого профиля
    private func revokeAppleAuth() {
        currentProfile.appleUserId = nil
        currentProfile.authType = currentProfile.gameCenterPlayerId != nil
            ? .guest // Только GC без Apple — всё равно guest-level
            : .guest
        currentProfile.displayName = "Гость"
        
        _ = KeychainHelper.delete(forKey: .appleUserId)
        saveProfile()
        
        delegate?.authServiceDidRevokeAppleAuth(self)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Обновление профиля
    // ═══════════════════════════════════════════════════════════════
    
    /// Применяет результат матча к профилю (MMR + статистика)
    public func recordMatchResult(_ result: MatchResult) {
        currentProfile.applyMatchResult(result)
        saveProfile()
        
        Self.logger.info(
            "Матч записан: \(result.rawValue) | MMR: \(self.currentProfile.mmr) | " +
            "W/L/D: \(self.currentProfile.stats.wins)/\(self.currentProfile.stats.losses)/\(self.currentProfile.stats.draws)"
        )
        
        delegate?.authService(self, didUpdateProfile: currentProfile)
    }
    
    /// Привязывает Game Center Player ID
    public func linkGameCenter(playerId: String) {
        currentProfile.gameCenterPlayerId = playerId
        
        if currentProfile.appleUserId != nil {
            currentProfile.authType = .appleAndGameCenter
        }
        
        saveProfile()
        
        Self.logger.info("Game Center привязан: \(playerId.prefix(8))...")
        delegate?.authService(self, didUpdateProfile: currentProfile)
    }
    
    /// Выход из аккаунта — возврат к гостевому режиму (сохраняет статистику)
    public func signOut() {
        Self.logger.info("Выход из аккаунта")
        
        currentProfile.appleUserId = nil
        currentProfile.gameCenterPlayerId = nil
        currentProfile.authType = .guest
        currentProfile.displayName = "Гость"
        
        _ = KeychainHelper.delete(forKey: .appleUserId)
        saveProfile()
        
        delegate?.authService(self, didUpdateProfile: currentProfile)
    }
    
    /// Полный сброс профиля (новый UUID, сброс статистики)
    public func resetProfile() {
        Self.logger.warning("Полный сброс профиля")
        
        _ = KeychainHelper.delete(forKey: .appleUserId)
        _ = KeychainHelper.delete(forKey: .playerProfile)
        UserDefaults.standard.removeObject(forKey: Self.profileUserDefaultsKey)
        
        currentProfile = PlayerProfile()
        saveProfile()
        
        delegate?.authService(self, didUpdateProfile: currentProfile)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Персистентность
    // ═══════════════════════════════════════════════════════════════
    
    /// Сохраняет профиль в UserDefaults + Keychain (двойная страховка)
    private func saveProfile() {
        Self.saveProfileToUserDefaults(currentProfile)
        _ = KeychainHelper.save(object: currentProfile, forKey: .playerProfile)
    }
    
    /// Сохраняет профиль только в UserDefaults
    private static func saveProfileToUserDefaults(_ profile: PlayerProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            logger.error("Не удалось сериализовать профиль для UserDefaults")
            return
        }
        UserDefaults.standard.set(data, forKey: profileUserDefaultsKey)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - ASAuthorizationControllerDelegate
// ═══════════════════════════════════════════════════════════════════

extension AuthService: ASAuthorizationControllerDelegate {
    
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        signInContinuation?.resume(returning: authorization)
        signInContinuation = nil
    }
    
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        signInContinuation?.resume(throwing: error)
        signInContinuation = nil
    }
}
