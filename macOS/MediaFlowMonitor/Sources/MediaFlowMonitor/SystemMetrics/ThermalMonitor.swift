import Foundation
import Combine

/// Nivel de throttling termic, portat 1:1 pe cele 4 stări ale
/// `ProcessInfo.ThermalState`.
enum ThermalState: Int, Comparable {
    case nominal, fair, serious, critical

    static func < (lhs: ThermalState, rhs: ThermalState) -> Bool { lhs.rawValue < rhs.rawValue }

    init(_ raw: ProcessInfo.ThermalState) {
        switch raw {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Ridicat"
        case .serious: return "Serios (throttling probabil)"
        case .critical: return "Critic (throttling activ)"
        }
    }

    var level: MetricLevel {
        switch self {
        case .nominal: return .ok
        case .fair: return .warning
        case .serious, .critical: return .critical
        }
    }
}

/// Monitor de temperatură/throttling — DECIZIE DE ARHITECTURĂ (2026-08-31):
/// macOS NU expune public temperatura reală CPU/GPU în grade (SMC e
/// nedocumentat, necesită chei private care pot dispărea la orice update
/// de OS și diferă per model de Mac — vezi discuția similară din
/// `VRAMProbe`/RAM-Swap). În loc să citim SMC neoficial (fragil, risc de
/// date greșite pe modele necunoscute), folosim `ProcessInfo.thermalState`
/// — API PUBLIC, DOCUMENTAT, actualizat de macOS însuși pe baza senzorilor
/// reali — și raportăm exact ce înseamnă pentru user: "cât de aproape e
/// sistemul de throttling", nu un număr de grade fals-precis. Onest, ca
/// eticheta "Top Swap Activity" de pe Mac (proxy documentat, nu o valoare
/// inventată).
final class ThermalMonitor {
    let statePublisher = CurrentValueSubject<ThermalState, Never>(ThermalState(ProcessInfo.processInfo.thermalState))

    private var observer: NSObjectProtocol?

    func start() {
        statePublisher.send(ThermalState(ProcessInfo.processInfo.thermalState))
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.statePublisher.send(ThermalState(ProcessInfo.processInfo.thermalState))
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
