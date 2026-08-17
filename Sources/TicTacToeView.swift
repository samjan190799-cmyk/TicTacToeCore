import SwiftUI

// ╔══════════════════════════════════════════════════════════════════╗
// ║  STYLE GUIDE — Neon Glassmorphism Dark Theme                    ║
// ║                                                                  ║
// ║  Концепция: Тёмная космическая тема с неоновым свечением.        ║
// ║  Стекло-панели парят над глубоким градиентом, а каждый ход       ║
// ║  игрока взрывается пружинной анимацией с цветным glow.          ║
// ║                                                                  ║
// ║  Палитра:                                                        ║
// ║    • Background:  #050510 → #0A0A1F (радиальный градиент)       ║
// ║    • Neon Cyan:   #00F5FF (X — атакующий, холодный)             ║
// ║    • Neon Magenta:#FF2D78 (O — дерзкий, тёплый)                 ║
// ║    • Win Gold:    #FFD700 → #FFA500 (подсветка победной линии)   ║
// ║    • Glass:       .ultraThinMaterial + white 8% fill             ║
// ║    • Glass Border:LinearGradient white 20%→5%                    ║
// ║                                                                  ║
// ║  Типографика: .rounded system font                               ║
// ║  Анимации: .interactiveSpring, каскадный scale+opacity           ║
// ║  Haptics: UIImpactFeedbackGenerator (medium/rigid)               ║
// ╚══════════════════════════════════════════════════════════════════╝

// MARK: - Дизайн-токены
/// Централизованные константы визуальной темы
private enum NeonTheme {
    // Цвета неона
    static let neonCyan    = Color(red: 0.0, green: 0.96, blue: 1.0)   // #00F5FF
    static let neonMagenta = Color(red: 1.0, green: 0.18, blue: 0.47)  // #FF2D78
    static let neonGold    = Color(red: 1.0, green: 0.84, blue: 0.0)   // #FFD700
    static let neonOrange  = Color(red: 1.0, green: 0.65, blue: 0.0)   // #FFA500
    static let neonPurple  = Color(red: 0.65, green: 0.35, blue: 1.0)  // #A659FF
    
    // Фон
    static let bgDeep   = Color(red: 0.02, green: 0.02, blue: 0.06)    // #050510
    static let bgMid    = Color(red: 0.04, green: 0.04, blue: 0.12)    // #0A0A1F
    static let bgAccent = Color(red: 0.08, green: 0.04, blue: 0.18)    // #140A2E
    
    // Стекло
    static let glassFill       = Color.white.opacity(0.08)
    static let glassBorderTop  = Color.white.opacity(0.20)
    static let glassBorderBot  = Color.white.opacity(0.05)
    
    // Скругления
    static let boardCorner: CGFloat  = 28
    static let cellCorner: CGFloat   = 18
    static let buttonCorner: CGFloat = 22
    
    /// Цвет неона для конкретного игрока
    static func playerColor(_ player: Player) -> Color {
        player == .x ? neonCyan : neonMagenta
    }
}

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Менеджер тактильного отклика
/// Централизованный Haptic Feedback (iOS)
struct HapticManager {
    static let shared = HapticManager()
    
    #if canImport(UIKit)
    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact  = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    #endif
    
    /// Подготовка генераторов к работе (снижает задержку первого отклика)
    func prepare() {
        #if canImport(UIKit)
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        notification.prepare()
        #endif
    }
    
    /// Лёгкий щелчок — переключение UI элементов
    func tapLight() {
        #if canImport(UIKit)
        lightImpact.impactOccurred()
        #endif
    }
    
    /// Средний удар — ход игрока
    func tapMedium() {
        #if canImport(UIKit)
        mediumImpact.impactOccurred()
        #endif
    }
    
    /// Жёсткий удар — ход ИИ
    func tapRigid() {
        #if canImport(UIKit)
        rigidImpact.impactOccurred()
        #endif
    }
    
    /// Уведомление об успехе (победа)
    func notifySuccess() {
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        #endif
    }
    
    /// Уведомление о предупреждении (ничья)
    func notifyWarning() {
        #if canImport(UIKit)
        notification.notificationOccurred(.warning)
        #endif
    }
    
    /// Уведомление об ошибке
    func notifyError() {
        #if canImport(UIKit)
        notification.notificationOccurred(.error)
        #endif
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - TicTacToeView (Главный экран)
// ═══════════════════════════════════════════════════════════════════

public struct TicTacToeView: View {
    @StateObject private var viewModel = GameViewModel()
    
    /// Анимация каскадного появления клеток при запуске
    @State private var boardAppeared = false
    
    /// Пульсация победной линии
    @State private var winPulse = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // ═══ Слой 1: Глубокий космический фон ═══
            backgroundLayer
            
            // ═══ Слой 2: Основной контент ═══
            VStack(spacing: 20) {
                // Заголовок с неоновым свечением
                titleView
                
                // Переключатель режима игры
                gameModePicker
                
                Spacer().frame(height: 4)
                
                // Карточка статуса (чей ход / ИИ думает)
                statusCard
                
                // Игровое поле 3x3
                boardGrid
                
                Spacer().frame(height: 4)
                
                // Кнопка «Новая игра»
                resetButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // ═══ Слой 3: Оверлей победы / ничьей ═══
            if viewModel.gameState.isGameOver {
                gameOverOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onAppear {
            HapticManager.shared.prepare()
            // Каскадное появление клеток поля
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                boardAppeared = true
            }
        }
        .onChange(of: viewModel.gameState) { _, newState in
            if newState.isGameOver {
                // Запуск пульсации при победе
                winPulse = false
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    winPulse = true
                }
                // Тактильный отклик при окончании игры
                if case .won = newState {
                    HapticManager.shared.notifySuccess()
                } else {
                    HapticManager.shared.notifyWarning()
                }
            } else {
                winPulse = false
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Фоновый слой
    // ═══════════════════════════════════════════════════════════════
    
    private var backgroundLayer: some View {
        ZStack {
            // Базовый радиальный градиент
            RadialGradient(
                colors: [NeonTheme.bgAccent, NeonTheme.bgMid, NeonTheme.bgDeep],
                center: .center,
                startRadius: 80,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            // Декоративные неоновые пятна размытого свечения
            Circle()
                .fill(NeonTheme.neonCyan.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: -120, y: -280)
            
            Circle()
                .fill(NeonTheme.neonMagenta.opacity(0.06))
                .frame(width: 250, height: 250)
                .blur(radius: 90)
                .offset(x: 140, y: 320)
            
            Circle()
                .fill(NeonTheme.neonPurple.opacity(0.05))
                .frame(width: 200, height: 200)
                .blur(radius: 80)
                .offset(x: 100, y: -100)
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Заголовок
    // ═══════════════════════════════════════════════════════════════
    
    private var titleView: some View {
        Text("КРЕСТИКИ-НОЛИКИ")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .tracking(3)
            .foregroundStyle(
                LinearGradient(
                    colors: [NeonTheme.neonCyan, NeonTheme.neonPurple, NeonTheme.neonMagenta],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: NeonTheme.neonCyan.opacity(0.5), radius: 12, y: 0)
            .shadow(color: NeonTheme.neonMagenta.opacity(0.3), radius: 20, y: 0)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Переключатель режима
    // ═══════════════════════════════════════════════════════════════
    
    private var gameModePicker: some View {
        HStack(spacing: 0) {
            ForEach(GameMode.allCases) { mode in
                let isSelected = viewModel.gameMode == mode
                
                Button {
                    HapticManager.shared.tapLight()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        viewModel.gameMode = mode
                        // Сброс каскадной анимации при смене режима
                        boardAppeared = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                boardAppeared = true
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode == .vsPlayer ? "person.2.fill" : "cpu")
                            .font(.caption)
                        Text(mode == .vsPlayer ? "Игрок" : "Компьютер")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                    .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [NeonTheme.neonCyan.opacity(0.3), NeonTheme.neonPurple.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(NeonTheme.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [NeonTheme.glassBorderTop, NeonTheme.glassBorderBot],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 8)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Карточка статуса
    // ═══════════════════════════════════════════════════════════════
    
    private var statusCard: some View {
        HStack(spacing: 10) {
            if viewModel.isAIThinking {
                aiThinkingIndicator
            } else {
                activeStatusContent
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [NeonTheme.glassBorderTop, NeonTheme.glassBorderBot],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: statusGlowColor.opacity(0.25), radius: 16, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: viewModel.gameState)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: viewModel.isAIThinking)
    }
    
    /// Индикатор «ИИ думает» с анимированными точками
    private var aiThinkingIndicator: some View {
        HStack(spacing: 8) {
            // Три пульсирующих неоновых точки
            ForEach(0..<3, id: \.self) { dotIndex in
                Circle()
                    .fill(NeonTheme.neonPurple)
                    .frame(width: 8, height: 8)
                    .shadow(color: NeonTheme.neonPurple.opacity(0.8), radius: 6)
                    .scaleEffect(viewModel.isAIThinking ? 1.3 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(dotIndex) * 0.15),
                        value: viewModel.isAIThinking
                    )
            }
            Text("ИИ думает")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(NeonTheme.neonPurple)
        }
    }
    
    /// Содержимое статуса в активном режиме (чей ход)
    @ViewBuilder
    private var activeStatusContent: some View {
        switch viewModel.gameState {
        case .active:
            HStack(spacing: 8) {
                Circle()
                    .fill(NeonTheme.playerColor(viewModel.currentPlayer))
                    .frame(width: 10, height: 10)
                    .shadow(
                        color: NeonTheme.playerColor(viewModel.currentPlayer).opacity(0.8),
                        radius: 6
                    )
                Text("Ход:")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                Text(viewModel.currentPlayer.rawValue)
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(NeonTheme.playerColor(viewModel.currentPlayer))
                    .shadow(
                        color: NeonTheme.playerColor(viewModel.currentPlayer).opacity(0.6),
                        radius: 8
                    )
            }
        case .won(let player):
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundColor(NeonTheme.neonGold)
                    .shadow(color: NeonTheme.neonGold.opacity(0.8), radius: 8)
                Text("\(player.rawValue) побеждает!")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(NeonTheme.playerColor(player))
                    .shadow(
                        color: NeonTheme.playerColor(player).opacity(0.6),
                        radius: 8
                    )
            }
        case .draw:
            HStack(spacing: 8) {
                Image(systemName: "equal.circle.fill")
                    .font(.title3)
                    .foregroundColor(NeonTheme.neonOrange)
                    .shadow(color: NeonTheme.neonOrange.opacity(0.8), radius: 8)
                Text("Ничья!")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(NeonTheme.neonOrange)
                    .shadow(color: NeonTheme.neonOrange.opacity(0.6), radius: 8)
            }
        }
    }
    
    /// Цвет свечения статус-карты в зависимости от состояния
    private var statusGlowColor: Color {
        if viewModel.isAIThinking { return NeonTheme.neonPurple }
        switch viewModel.gameState {
        case .active:       return NeonTheme.playerColor(viewModel.currentPlayer)
        case .won(let p):   return NeonTheme.playerColor(p)
        case .draw:         return NeonTheme.neonOrange
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Игровое поле 3x3
    // ═══════════════════════════════════════════════════════════════
    
    private var boardGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(viewModel.board.enumerated()), id: \.element.id) { index, cell in
                NeonCellView(
                    cell: cell,
                    index: index,
                    isWinning: viewModel.winningIndices.contains(index),
                    winPulse: winPulse,
                    isDisabled: cell.isOccupied || viewModel.gameState.isGameOver || viewModel.isAIThinking,
                    appeared: boardAppeared
                ) {
                    // Обработка нажатия
                    HapticManager.shared.tapMedium()
                    withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.25)) {
                        viewModel.makeMove(at: index)
                    }
                }
            }
        }
        .padding(14)
        .background(
            // Стеклянная панель поля
            RoundedRectangle(cornerRadius: NeonTheme.boardCorner, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: NeonTheme.boardCorner, style: .continuous)
                        .fill(NeonTheme.glassFill)
                )
                .overlay(
                    // Градиентная рамка стекла
                    RoundedRectangle(cornerRadius: NeonTheme.boardCorner, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [NeonTheme.glassBorderTop, NeonTheme.glassBorderBot],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: NeonTheme.neonPurple.opacity(0.08), radius: 30, y: 10)
        )
        .aspectRatio(1, contentMode: .fit)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Кнопка «Новая игра»
    // ═══════════════════════════════════════════════════════════════
    
    private var resetButton: some View {
        Button {
            HapticManager.shared.tapLight()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                viewModel.resetGame()
                winPulse = false
                // Перезапуск каскадной анимации
                boardAppeared = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    boardAppeared = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.trianglehead.2.counterclockwise")
                    .font(.system(.body, design: .rounded).weight(.bold))
                Text("Новая игра")
                    .font(.system(.headline, design: .rounded).weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                NeonTheme.neonCyan.opacity(0.6),
                                NeonTheme.neonPurple.opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [NeonTheme.glassBorderTop, NeonTheme.glassBorderBot],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: NeonTheme.neonCyan.opacity(0.3), radius: 14, y: 4)
            .shadow(color: NeonTheme.neonPurple.opacity(0.2), radius: 20, y: 6)
        }
        .buttonStyle(NeonPressStyle())
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Оверлей окончания игры
    // ═══════════════════════════════════════════════════════════════
    
    private var gameOverOverlay: some View {
        ZStack {
            // Затемнённый фон с blur
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {} // Блокировка нажатий на поле
            
            // Стеклянная карточка результата
            VStack(spacing: 24) {
                // Иконка результата
                resultIcon
                    .font(.system(size: 56))
                    .shadow(color: resultGlowColor.opacity(0.8), radius: 20)
                    .shadow(color: resultGlowColor.opacity(0.4), radius: 40)
                
                // Текст результата
                resultTitle
                
                // Декоративная линия-разделитель
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.clear, resultGlowColor.opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .padding(.horizontal, 20)
                
                // Кнопка рестарта в оверлее
                Button {
                    HapticManager.shared.tapRigid()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        viewModel.resetGame()
                        winPulse = false
                        boardAppeared = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                            boardAppeared = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Играть снова")
                    }
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [resultGlowColor.opacity(0.7), resultGlowColor.opacity(0.4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(resultGlowColor.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: resultGlowColor.opacity(0.4), radius: 16, y: 4)
                }
                .buttonStyle(NeonPressStyle())
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [resultGlowColor.opacity(0.4), NeonTheme.glassBorderBot],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: resultGlowColor.opacity(0.2), radius: 40, y: 10)
            .padding(.horizontal, 40)
        }
    }
    
    /// Иконка результата (корона при победе, весы при ничьей)
    @ViewBuilder
    private var resultIcon: some View {
        switch viewModel.gameState {
        case .won(let player):
            Image(systemName: "crown.fill")
                .foregroundColor(NeonTheme.playerColor(player))
        case .draw:
            Image(systemName: "scalemass.fill")
                .foregroundColor(NeonTheme.neonOrange)
        default:
            EmptyView()
        }
    }
    
    /// Заголовок результата
    @ViewBuilder
    private var resultTitle: some View {
        switch viewModel.gameState {
        case .won(let player):
            VStack(spacing: 6) {
                Text("ПОБЕДА")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundColor(NeonTheme.playerColor(player))
                    .shadow(color: NeonTheme.playerColor(player).opacity(0.6), radius: 10)
                Text("Игрок \(player.rawValue)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        case .draw:
            Text("НИЧЬЯ")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .tracking(4)
                .foregroundColor(NeonTheme.neonOrange)
                .shadow(color: NeonTheme.neonOrange.opacity(0.6), radius: 10)
        default:
            EmptyView()
        }
    }
    
    /// Цвет свечения для оверлея результата
    private var resultGlowColor: Color {
        switch viewModel.gameState {
        case .won(let player): return NeonTheme.playerColor(player)
        case .draw:            return NeonTheme.neonOrange
        default:               return NeonTheme.neonPurple
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - NeonCellView (Ячейка поля с неоновым свечением)
// ═══════════════════════════════════════════════════════════════════

/// Отдельная ячейка игрового поля с полным набором эффектов:
/// каскадное появление, неоновое свечение знака, пульсация победной клетки
private struct NeonCellView: View {
    let cell: Cell
    let index: Int
    let isWinning: Bool
    let winPulse: Bool
    let isDisabled: Bool
    let appeared: Bool
    let action: () -> Void
    
    /// Анимация появления знака внутри ячейки
    @State private var symbolScale: CGFloat = 0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // --- Фон ячейки ---
                cellBackground
                
                // --- Знак игрока (X / O) ---
                if let player = cell.player {
                    neonSymbol(for: player)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // Каскадная анимация появления при старте/сбросе
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.7)
        .animation(
            .spring(response: 0.45, dampingFraction: 0.72)
            .delay(Double(index) * 0.04),
            value: appeared
        )
        // Отслеживаем появление знака для пружинной анимации
        .onChange(of: cell.player) { _, newPlayer in
            if newPlayer != nil {
                symbolScale = 0
                withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.55, blendDuration: 0.2)) {
                    symbolScale = 1
                }
            } else {
                symbolScale = 0
            }
        }
    }
    
    // MARK: - Фон ячейки
    
    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: NeonTheme.cellCorner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: NeonTheme.cellCorner, style: .continuous)
                    .fill(cellFillColor)
            )
            .overlay(
                // Рамка ячейки: обычная или победная
                RoundedRectangle(cornerRadius: NeonTheme.cellCorner, style: .continuous)
                    .stroke(cellBorderGradient, lineWidth: isWinning ? 2 : 1)
            )
            // Внешнее свечение победной ячейки
            .shadow(
                color: isWinning
                    ? NeonTheme.neonGold.opacity(winPulse ? 0.6 : 0.2)
                    : Color.clear,
                radius: isWinning ? 14 : 0
            )
    }
    
    /// Цвет заливки ячейки
    private var cellFillColor: Color {
        if isWinning {
            return NeonTheme.neonGold.opacity(winPulse ? 0.15 : 0.08)
        }
        return NeonTheme.glassFill
    }
    
    /// Градиент рамки ячейки
    private var cellBorderGradient: LinearGradient {
        if isWinning {
            return LinearGradient(
                colors: [
                    NeonTheme.neonGold.opacity(winPulse ? 0.9 : 0.5),
                    NeonTheme.neonOrange.opacity(winPulse ? 0.7 : 0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [NeonTheme.glassBorderTop, NeonTheme.glassBorderBot],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Неоновый знак игрока
    
    /// Знак X или O с многослойным неоновым свечением
    private func neonSymbol(for player: Player) -> some View {
        let color = NeonTheme.playerColor(player)
        
        return Text(player.rawValue)
            .font(.system(size: 44, weight: .black, design: .rounded))
            .foregroundColor(color)
            // Слой 1: ближнее чёткое свечение
            .shadow(color: color.opacity(0.9), radius: 4, y: 0)
            // Слой 2: среднее свечение
            .shadow(color: color.opacity(0.6), radius: 12, y: 0)
            // Слой 3: дальнее рассеянное свечение
            .shadow(color: color.opacity(0.3), radius: 24, y: 0)
            // Пружинная анимация появления
            .scaleEffect(symbolScale)
            .opacity(Double(symbolScale))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - NeonPressStyle (Стиль кнопки с эффектом нажатия)
// ═══════════════════════════════════════════════════════════════════

/// Кастомный ButtonStyle: уменьшение + снижение яркости при нажатии
private struct NeonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
