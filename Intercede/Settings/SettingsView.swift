import SwiftUI

struct SettingsView: View {
    @ObservedObject var usageTracker: UsageTracker
    @ObservedObject var patronLibrary: PatronLibrary
    @State private var newHost = ""

    var body: some View {
        TabView {
            SitesTab(usageTracker: usageTracker, newHost: $newHost)
                .tabItem { Label("Sites", systemImage: "globe") }

            PatronTab(patronLibrary: patronLibrary)
                .tabItem { Label("Patron", systemImage: "hands.sparkles.fill") }
        }
        .frame(width: 440, height: 380)
        .padding()
    }
}

struct SitesTab: View {
    @ObservedObject var usageTracker: UsageTracker
    @Binding var newHost: String
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracked Sites")
                .font(.system(size: 13, weight: .semibold))

            List {
                ForEach($usageTracker.siteConfigs) { $config in
                    HStack {
                        Text(config.host)
                            .font(.system(size: 12))
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
                                .font(.system(size: 12))
                                .frame(width: 60)
                        }
                        Button {
                            usageTracker.removeSite(config.host)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop tracking \(config.host)")
                        .accessibilityLabel("Remove \(config.host)")
                    }
                }
                .onDelete { indices in
                    usageTracker.siteConfigs.remove(atOffsets: indices)
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("new site (e.g. twitch.tv)", text: $newHost)
                    .font(.system(size: 12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: newHost) { rejected = false }
                Button("Add", action: add)
                    .disabled(newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if rejected {
                Text("Not a valid site, or already tracked.")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    private func add() {
        if usageTracker.addSite(newHost) {
            newHost = ""
        } else {
            rejected = true
        }
    }
}

struct PatronTab: View {
    @ObservedObject var patronLibrary: PatronLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Patron")
                .font(.system(size: 13, weight: .semibold))

            Picker("Patron", selection: $patronLibrary.selectedPatronSlug) {
                ForEach(patronLibrary.availablePatrons) { patron in
                    Text(patron.name).tag(patron.slug)
                }
            }

            let current = patronLibrary.current
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    SpriteView(sheet: current.sheet, animation: .idle, height: 140)
                    Text("“\(current.patron.catchphrase)”")
                        .font(.system(size: 12, weight: .bold))
                }
                Spacer()
            }

            Spacer()
        }
        .padding()
    }
}
