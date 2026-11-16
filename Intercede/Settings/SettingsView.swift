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
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracked Sites")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach($usageTracker.siteConfigs) { $config in
                        HStack {
                            Text(config.host)
                                .font(.system(size: 12))
                            Spacer()
                            TextField("", value: minutes($config), format: .number)
                                .font(.system(size: 12))
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 52)
                            Stepper("", value: minutes($config), in: Self.minuteRange, step: 5)
                                .labelsHidden()
                            Text("min/day")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .tag(config.host)
                    }
                    .onDelete { indices in
                        usageTracker.siteConfigs.remove(atOffsets: indices)
                    }
                }
                .onDeleteCommand(perform: removeSelected)
                .frame(minHeight: 160)

                Divider()
                // macOS list-editor bar: remove the selected site, or type one to add.
                HStack(spacing: 8) {
                    Button(action: removeSelected) {
                        Image(systemName: "minus")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    .help("Remove the selected site")
                    Divider().frame(height: 16)
                    TextField("Add a site (e.g. twitch.tv)", text: $newHost)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                        .onChange(of: newHost) { rejected = false }
                    Button("Add", action: add)
                        .disabled(newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            if rejected {
                Text("Not a valid site, or already tracked.")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    static let minuteRange = 1...1440

    /// A site's daily budget in whole minutes, clamped to 1 minute–24 hours.
    private func minutes(_ config: Binding<SiteConfig>) -> Binding<Int> {
        Binding(
            get: { Int(config.wrappedValue.dailyBudgetSeconds / 60) },
            set: { config.wrappedValue.dailyBudgetSeconds = Double(min(max($0, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)) * 60 }
        )
    }

    private func removeSelected() {
        guard let host = selection else { return }
        usageTracker.removeSite(host)
        selection = nil
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
