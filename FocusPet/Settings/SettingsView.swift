import SwiftUI

struct SettingsView: View {
    @StateObject private var usageTracker = UsageTracker()
    @State private var newHost = ""
    @State private var apiKey = Keychain.load(forKey: "anthropicAPIKey") ?? ""
    @State private var showAPIKeyMismatch = false

    var body: some View {
        TabView {
            SitesTab(usageTracker: usageTracker, newHost: $newHost)
                .tabItem { Label("Sites", systemImage: "globe") }

            APIKeyTab(apiKey: $apiKey)
                .tabItem { Label("API", systemImage: "key.fill") }
        }
        .frame(width: 420, height: 360)
        .padding()
    }
}

struct SitesTab: View {
    @ObservedObject var usageTracker: UsageTracker
    @Binding var newHost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracked Sites")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            List {
                ForEach($usageTracker.siteConfigs) { $config in
                    HStack {
                        Text(config.host)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minWidth: 140, alignment: .leading)
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { config.dailyBudgetSeconds / 60 },
                                set: { config.dailyBudgetSeconds = $0 * 60 }
                            ),
                            in: 1...480,
                            step: 5
                        ) {
                            Text("\(Int(config.dailyBudgetSeconds / 60)) min")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 60)
                        }
                    }
                }
                .onDelete { indices in
                    usageTracker.siteConfigs.remove(atOffsets: indices)
                    usageTracker.saveSiteConfigs()
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("new site (e.g. twitch.tv)", text: $newHost)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let host = newHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !host.isEmpty, !usageTracker.siteConfigs.contains(where: { $0.host == host }) else { return }
                    usageTracker.siteConfigs.append(SiteConfig(host: host, dailyBudgetSeconds: 15 * 60))
                    usageTracker.saveSiteConfigs()
                    newHost = ""
                }
                .disabled(newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}

struct APIKeyTab: View {
    @Binding var apiKey: String
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anthropic API Key")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text("Used to generate personalized nudge messages. Falls back to built-in messages if blank.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            SecureField("sk-ant-...", text: $apiKey)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save") {
                    Keychain.save(apiKey, forKey: "anthropicAPIKey")
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                }
                if saved {
                    Text("Saved!")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                }
            }

            Spacer()
        }
        .padding()
    }
}
