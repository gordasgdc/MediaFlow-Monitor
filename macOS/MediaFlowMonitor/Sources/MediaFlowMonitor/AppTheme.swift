import AppKit
import Combine

enum AppTheme: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil // nil = urmează setarea sistemului
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Selector explicit Dark/Light/System, independent de setarea macOS —
/// cerut explicit: unii clienți vor Light chiar și noaptea, alții Dark permanent.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let key = "MediaFlowMonitor.appTheme"

    @Published var current: AppTheme {
        didSet { apply() }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        current = saved.flatMap(AppTheme.init(rawValue:)) ?? .system
        apply()
    }

    func set(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
        current = theme
    }

    private func apply() {
        NSApp.appearance = current.nsAppearance
    }
}
