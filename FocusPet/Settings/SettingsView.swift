import SwiftUI

struct SettingsView: View {
    @ObservedObject var usageTracker: UsageTracker
    @ObservedObject var petLibrary: PetLibrary
    @State private var newHost = ""

    var body: some View {
        TabView {
            SitesTab(usageTracker: usageTracker, newHost: $newHost)
                .tabItem { Label("Sites", systemImage: "globe") }

            PetTab(petLibrary: petLibrary)
                .tabItem { Label("Pet", systemImage: "pawprint.fill") }
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
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("new site (e.g. twitch.tv)", text: $newHost)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: newHost) { rejected = false }
                Button("Add", action: add)
                    .disabled(newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if rejected {
                Text("Not a valid site, or already tracked.")
                    .font(.system(size: 11, design: .monospaced))
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

struct PetTab: View {
    @ObservedObject var petLibrary: PetLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Companion")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            Picker("Pet", selection: $petLibrary.selectedPetSlug) {
                ForEach(petLibrary.availablePets) { pet in
                    Text(pet.name).tag(pet.slug)
                }
            }

            let current = petLibrary.current
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    SpriteView(sheet: current.sheet, animation: .idle, height: 140)
                    Text("“\(current.pet.catchphrase)”")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Spacer()
            }

            Text("More companions join as their artwork is added.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
