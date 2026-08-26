import SwiftUI
import AppKit

/// Fereastra nativă "Despre" — logo, versiune + build, statut licență,
/// Machine ID scurtat cu copiere rapidă. Accesibilă din meniul de sus
/// (App menu → Despre MediaFlow Monitor) și din meniul status item-ului.
struct AboutView: View {
    @ObservedObject var license: LicenseManager
    @State private var copied = false

    private var appIcon: NSImage { NSApp.applicationIconImage ?? NSImage() }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private var licenseStatusText: String {
        switch license.state {
        case .trial(let daysLeft): return "Probă gratuită — \(daysLeft) zile rămase"
        case .trialExpired: return "Probă expirată — activare necesară"
        case .licensed(let expiresAt): return expiresAt == 0 ? "Licențiat (Lifetime)" : "Licențiat"
        }
    }

    private var licenseStatusColor: Color {
        switch license.state {
        case .trial: return .yellow
        case .trialExpired: return .red
        case .licensed: return .green
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 20)

            Text("MediaFlow Monitor").font(.title2.bold())
            Text("v\(version) (build \(build))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 30)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(licenseStatusColor).frame(width: 8, height: 8)
                    Text(licenseStatusText).font(.system(size: 12))
                }
                HStack(spacing: 6) {
                    Text("Machine ID:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(shortMachineID).font(.system(size: 11, design: .monospaced))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(license.machineIDDisplay, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copiază Machine ID complet")
                }
            }

            Spacer()

            Text("Parte din ecosistemul GDC · gordas.dev")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(width: 340, height: 400)
    }

    /// Machine ID complet e lung (SHA-derivat) — afișăm doar primele/ultimele
    /// caractere, ca într-un card bancar; copierea rapidă ia mereu valoarea completă.
    private var shortMachineID: String {
        let full = license.machineIDDisplay
        guard full.count > 14 else { return full }
        let prefix = full.prefix(6)
        let suffix = full.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
