# 🎮 TicTacToeCore — Игровое ядро "Крестики-Нолики" для iOS

Модульное игровое ядро для iOS на **Swift 6 / SwiftUI (MVVM)** с поддержкой офлайн-игры против непобедимого ИИ (Minimax), мультиплеера по WebSocket, аутентификации через Apple ID / Game Center и премиального интерфейса Neon Glassmorphism.

---

## 🌟 Основные возможности

1. **Игровая логика (MVVM)**
   - Реактивное состояние через `@Published` и изоляцию на `@MainActor`.
   - Валидация ходов, выявление 8 победных паттернов, ничьи и подсветка победных линий.
   
2. **Интеллектуальный ИИ (Minimax)**
   - Алгоритм полного перебора состояний с весовыми коэффициентами (+10 победа, -10 поражение, 0 ничья) с учётом глубины `depth`.
   - Плавная задержка хода бота 0.4 секунды для комфортного UX.

3. **Сетевой мультиплеер (WebSocket)**
   - Полнофункциональный `NetworkGameService` на базе `URLSessionWebSocketTask`.
   - Подключение по коду комнаты (`roomId`) и автоматический матчмейкинг.
   - Таймер матчмейкинга (15 секунд) с бесшовным fallback на Minimax-бота.
   - Exponential Backoff при переподключении и Heartbeat Ping/Pong (10 секунд).

4. **Аутентификация и профиль (Auth / Game Center)**
   - **Sign in with Apple** (`AuthenticationServices`): автоматический гостевой UUID-профиль с возможностью привязки Apple ID.
   - **Game Center** (`GKLocalPlayer`): глобальные лидерборды (MMR, Wins, Streak) и 11 встроенных достижений.
   - Двойное сохранение профиля и MMR рейтинга: `UserDefaults` + `iOS Keychain`.

5. **Премиальный интерфейс SwiftUI**
   - Тёмный неоновый стиль (Neon Glassmorphism) с материалами `.ultraThinMaterial`.
   - Многослойное неоновое свечение (Glow Effect), пружинные анимации (`.interactiveSpring`).
   - Тактильный отклик (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`).

---

## 📁 Структура проекта

```
TicTacToeCore/
├── Package.swift                 — Манифест Swift Package Manager
├── .gitignore                    — Исключения для Swift/Xcode
├── .github/
│   └── workflows/
│       └── ci.yml               — GitHub Actions CI пайплайн
├── Sources/
│   ├── Models.swift             — Доменные модели (Player, GameState, GameMode, Cell)
│   ├── TicTacToeAI.swift        — Minimax-бот
│   ├── GameViewModel.swift      — MVVM ViewModel игры
│   ├── NetworkModels.swift      — Codable-сообщения WebSocket
│   ├── NetworkGameService.swift — Сетевой сервис мультиплеера
│   ├── TicTacToeView.swift      — Неоновый Glassmorphism интерфейс
│   └── Auth/
│       ├── PlayerProfile.swift  — Профиль игрока, MMR и ранги
│       ├── KeychainHelper.swift — Хранение в iOS Keychain
│       ├── AuthService.swift    — Sign in with Apple и гостевой профиль
│       └── GameCenterService.swift — Game Center лидерборды и ачивки
└── Tests/
    ├── GameViewModelTests.swift      — Юнит-тесты логики и ИИ
    ├── NetworkGameServiceTests.swift — Тесты сетевых моделей
    └── AuthModuleTests.swift         — Тесты профиля, MMR и Keychain
```

---

## 📲 Установка .IPA на iPhone / iPad

1. Перейдите во вкладку **[Releases](https://github.com/samjan190799-cmyk/TicTacToeCore/releases)** репозитория.
2. Скачайте файл **`TicTacToe.ipa`**.
3. Установите на устройство любым удобным способом:
   - **AltStore / AltServer**
   - **Sideloadly** (macOS / Windows)
   - **TrollStore** (для совместимых версий iOS)
   - **Scarlet / GBox / Esign**

---

## 🛠 Требования

- **iOS 17.0+** / **macOS 14.0+**
- **Xcode 16.0+**
- **Swift 6.0+**
