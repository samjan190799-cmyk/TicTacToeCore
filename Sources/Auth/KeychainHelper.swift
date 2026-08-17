import Foundation
import Security

// ═══════════════════════════════════════════════════════════════════
// MARK: - KeychainHelper
// ═══════════════════════════════════════════════════════════════════
//
// Безопасное хранение чувствительных данных (Apple User ID, токены)
// в iOS Keychain через Security.framework.
//
// Статический анализ:
// ─────────────────
// • Все операции возвращают Result — нет необработанных ошибок
// • Данные кодируются/декодируются через JSONEncoder — нет ручного разбора
// • Keychain items помечены kSecAttrAccessibleAfterFirstUnlock —
//   доступны в фоне после первой разблокировки, но защищены до неё
// • Service key привязан к Bundle ID — нет конфликтов между приложениями
//
// ═══════════════════════════════════════════════════════════════════

/// Ошибки операций с Keychain
public enum KeychainError: Error, Sendable, CustomStringConvertible {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case dataConversionFailed
    case itemNotFound
    
    public var description: String {
        switch self {
        case .saveFailed(let status):
            return "Keychain: ошибка сохранения (OSStatus: \(status))"
        case .loadFailed(let status):
            return "Keychain: ошибка чтения (OSStatus: \(status))"
        case .deleteFailed(let status):
            return "Keychain: ошибка удаления (OSStatus: \(status))"
        case .dataConversionFailed:
            return "Keychain: ошибка конвертации данных"
        case .itemNotFound:
            return "Keychain: элемент не найден"
        }
    }
}

/// Потокобезопасный хелпер для работы с iOS Keychain.
/// Все методы — статические, без мутабельного состояния.
public enum KeychainHelper: Sendable {
    
    /// Идентификатор сервиса (привязан к Bundle ID)
    private static let service = Bundle.main.bundleIdentifier ?? "com.tictactoe.core"
    
    // MARK: - Ключи Keychain
    
    /// Ключи для хранения данных в Keychain
    public enum Key: String, Sendable {
        case appleUserId       = "apple_user_id"
        case playerProfile     = "player_profile"
        case authToken         = "auth_token"
    }
    
    // MARK: - Сохранение
    
    /// Сохраняет строку в Keychain
    /// - Parameters:
    ///   - value: Строковое значение
    ///   - key: Ключ для хранения
    /// - Returns: Result с успехом или ошибкой
    @discardableResult
    public static func save(string value: String, forKey key: Key) -> Result<Void, KeychainError> {
        guard let data = value.data(using: .utf8) else {
            return .failure(.dataConversionFailed)
        }
        return save(data: data, forKey: key)
    }
    
    /// Сохраняет Codable-объект в Keychain
    /// - Parameters:
    ///   - object: Codable-объект
    ///   - key: Ключ для хранения
    /// - Returns: Result с успехом или ошибкой
    @discardableResult
    public static func save<T: Encodable>(object: T, forKey key: Key) -> Result<Void, KeychainError> {
        do {
            let data = try JSONEncoder().encode(object)
            return save(data: data, forKey: key)
        } catch {
            return .failure(.dataConversionFailed)
        }
    }
    
    /// Сохраняет сырые данные в Keychain (базовый метод)
    @discardableResult
    public static func save(data: Data, forKey key: Key) -> Result<Void, KeychainError> {
        // Сначала пытаемся удалить существующий элемент
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Сохраняем новый элемент
        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    key.rawValue,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            return .success(())
        } else {
            return .failure(.saveFailed(status: status))
        }
    }
    
    // MARK: - Чтение
    
    /// Загружает строку из Keychain
    /// - Parameter key: Ключ элемента
    /// - Returns: Result со строкой или ошибкой
    public static func loadString(forKey key: Key) -> Result<String, KeychainError> {
        let dataResult = loadData(forKey: key)
        
        switch dataResult {
        case .success(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                return .failure(.dataConversionFailed)
            }
            return .success(string)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Загружает Codable-объект из Keychain
    /// - Parameters:
    ///   - type: Тип объекта для декодирования
    ///   - key: Ключ элемента
    /// - Returns: Result с объектом или ошибкой
    public static func loadObject<T: Decodable>(_ type: T.Type, forKey key: Key) -> Result<T, KeychainError> {
        let dataResult = loadData(forKey: key)
        
        switch dataResult {
        case .success(let data):
            do {
                let object = try JSONDecoder().decode(type, from: data)
                return .success(object)
            } catch {
                return .failure(.dataConversionFailed)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Загружает сырые данные из Keychain (базовый метод)
    public static func loadData(forKey key: Key) -> Result<Data, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                return .failure(.dataConversionFailed)
            }
            return .success(data)
        case errSecItemNotFound:
            return .failure(.itemNotFound)
        default:
            return .failure(.loadFailed(status: status))
        }
    }
    
    // MARK: - Удаление
    
    /// Удаляет элемент из Keychain
    /// - Parameter key: Ключ элемента
    /// - Returns: Result с успехом или ошибкой
    @discardableResult
    public static func delete(forKey key: Key) -> Result<Void, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            // errSecItemNotFound — не ошибка при удалении (идемпотентность)
            return .success(())
        default:
            return .failure(.deleteFailed(status: status))
        }
    }
    
    /// Удаляет все элементы приложения из Keychain
    @discardableResult
    public static func deleteAll() -> Result<Void, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return .success(())
        default:
            return .failure(.deleteFailed(status: status))
        }
    }
    
    // MARK: - Проверка наличия
    
    /// Проверяет, существует ли элемент в Keychain
    /// - Parameter key: Ключ элемента
    /// - Returns: true, если элемент существует
    public static func exists(forKey key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
