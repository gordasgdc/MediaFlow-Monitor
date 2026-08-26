import SwiftUI
import Combine

/// UI 100% vizual: semafoare de stare + carduri de acțiune cu un buton.
/// Fără tabele, fără text lung.
struct OverlayView: View {
    @ObservedObject private var viewModel: OverlayViewModel

    init(metrics: SystemMetrics, logWatcher: DaVinciLogWatcher?) {
        _viewModel = ObservedObject(wrappedValue: OverlayViewModel(metrics: metrics, logWatcher: logWatcher))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(String(localized: "overlay.title", bundle: .module))
                    .font(.headline)
                Spacer()
                StatusDot(level: viewModel.overallLevel)
            }

            MetricRing(label: String(localized: "metric.ram", bundle: .module), value: viewModel.ramFraction, level: viewModel.ramLevel)
            MetricRing(label: String(localized: "metric.swap", bundle: .module), value: viewModel.swapFraction, level: viewModel.swapLevel)

            if let action = viewModel.suggestedAction {
                ActionCard(action: action) { viewModel.perform(action) }
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatusDot: View {
    let level: MetricLevel
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .shadow(color: color.opacity(0.6), radius: 4)
    }
    private var color: Color {
        switch level {
        case .ok: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

private struct MetricRing: View {
    let label: String
    let value: Double // 0...1
    let level: MetricLevel

    var body: some View {
        HStack {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: value)
            }
            .frame(width: 36, height: 36)

            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(Int(value * 100))%")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
    private var color: Color {
        switch level {
        case .ok: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

private struct ActionCard: View {
    let action: SuggestedAction
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: action.icon)
                Text(action.title)
                Spacer()
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
