import SwiftUI

struct StatsView: View {
    @ObservedObject var usageTracker: UsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S FOCUS STATS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if usageTracker.siteConfigs.isEmpty {
                Text("No sites configured.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(usageTracker.siteConfigs) { config in
                    SiteBudgetRow(
                        host: config.host,
                        used: usageTracker.seconds(for: config.host),
                        budget: config.dailyBudgetSeconds
                    )
                }
            }
        }
        .padding()
    }
}

struct SiteBudgetRow: View {
    let host: String
    let used: Double
    let budget: Double

    private var fraction: Double { min(used / max(budget, 1), 1.0) }
    private var isOverBudget: Bool { used >= budget }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(host)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(formatTime(used))
                    .font(.system(size: 11))
                    .foregroundColor(isOverBudget ? .red : .primary)
                Text("/ \(formatTime(budget))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isOverBudget ? Color.red : Color.green)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m\(s)s" }
        return "\(s)s"
    }
}
