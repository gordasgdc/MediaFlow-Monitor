import Foundation
import Combine

/// Preferințele de comportament ale aplicației.
///
/// `UserDefaults` direct, fără fișier propriu: sunt trei comutatoare, iar
/// `@AppStorage` n-ar funcționa aici — panoul e construit dintr-un
/// `NSWindowController`, nu dintr-o scenă SwiftUI cu environment propriu.
final class MFMPreferences: ObservableObject {
    static let shared = MFMPreferences()

    private enum Key {
        static let startMinimized = "mfm.startMinimized"
        static let suppressPurgeWarning = "mfm.suppressPurgeWarning"
        static let suppressOptimiseWarning = "mfm.suppressOptimiseWarning"
    }

    /// Implicit `false`: la prima lansare panoul TREBUIE să apară.
    /// Fără fereastră și fără icon în Dock, un utilizator nou crede că
    /// aplicația n-a pornit — exact bug-ul reparat în
    /// `applicationDidFinishLaunching`. Comutatorul e o alegere pe care o
    /// face utilizatorul DUPĂ ce știe că aplicația există.
    @Published var startMinimized: Bool {
        didSet { UserDefaults.standard.set(startMinimized, forKey: Key.startMinimized) }
    }

    @Published var suppressPurgeWarning: Bool {
        didSet { UserDefaults.standard.set(suppressPurgeWarning, forKey: Key.suppressPurgeWarning) }
    }

    @Published var suppressOptimiseWarning: Bool {
        didSet { UserDefaults.standard.set(suppressOptimiseWarning, forKey: Key.suppressOptimiseWarning) }
    }

    private init() {
        let defaults = UserDefaults.standard
        startMinimized = defaults.bool(forKey: Key.startMinimized)
        suppressPurgeWarning = defaults.bool(forKey: Key.suppressPurgeWarning)
        suppressOptimiseWarning = defaults.bool(forKey: Key.suppressOptimiseWarning)
    }

    /// Scurtătura globală, într-un singur loc.
    ///
    /// Citită din `GlobalShortcut`, NU scrisă de mână: un banner care afișează
    /// altă combinație decât cea înregistrată efectiv e mai rău decât niciun
    /// banner. (Cererea inițială menționa `Option + Space`; scurtătura reală
    /// a acestei aplicații e ⌘⇧M — vezi GlobalShortcut.register.)
    static let shortcutDisplay = "⌘⇧M"
    static let shortcutPlainText = "Command + Shift + M"
}
