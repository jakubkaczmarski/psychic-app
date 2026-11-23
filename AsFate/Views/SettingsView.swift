import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var checking = false
    @State private var notificationsBlocked = false
    @State private var showPaywall = false
    @State private var manageSubscription = false
    @State private var restoring = false
    @State private var restoreMessage: String?

    private var status: (icon: String, color: Color, text: String) {
        if !app.isLive { return ("wand.and.stars", Theme.gold, "Demo mode: replies are pre-written") }
        switch app.serverOnline {
        case true?: return ("checkmark.seal.fill", Theme.online, "Connected · live readings are on")
        case false?: return ("wifi.exclamationmark", Theme.gold, "Can't reach this server")
        case nil: return ("questionmark.circle", Theme.muted, "Not checked yet")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: status.icon).foregroundStyle(status.color)
                        Text(status.text)
                    }
                    TextField("https://your-server.example.com", text: $app.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button {
                        checking = true
                        Task { await app.checkServer(); checking = false }
                    } label: {
                        HStack {
                            Text("Check connection")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!app.isLive || checking)
                    if app.serverURL != ReadingClient.defaultServerURL {
                        Button("Use online server") { app.serverURL = ReadingClient.defaultServerURL }
                    }
                    if app.serverURL != ReadingClient.localServerURL {
                        Button("Use local server (this Mac)") { app.serverURL = ReadingClient.localServerURL }
                    }
                } header: {
                    Text("Reading server")
                } footer: {
                    Text("Readings come from the As Fate Would Have It server. Leave the address empty for demo mode.")
                }

                Section("You") {
                    TextField("First name", text: $app.userName)
                    Picker("Star sign", selection: Binding(get: { app.sign ?? "" }, set: { app.sign = $0.isEmpty ? nil : $0 })) {
                        Text("Not set").tag("")
                        ForEach(Catalog.signs) { Text($0.name).tag($0.name) }
                    }
                }

                Section {
                    Picker("Your psychic", selection: $app.matchedPsychicID) {
                        ForEach(Catalog.psychics) { Text($0.name).tag($0.id) }
                    }
                    Toggle("Morning messages", isOn: Binding(
                        get: { app.morningMessagesOn },
                        set: { on in
                            if on { Task { if !(await app.enableMorningMessages()) { notificationsBlocked = true } } }
                            else { app.morningMessagesOn = false }
                        }))
                    #if DEBUG
                    Button("Debug: send a morning message in 5 seconds") { app.sendTestMorningMessage() }
                    #endif
                } header: {
                    Text("Daily")
                } footer: {
                    Text(notificationsBlocked
                         ? "Notifications are turned off for As Fate Would Have It. You can allow them in the iPhone Settings app."
                         : "Your psychic reads your card of the day and sends a message at \(MorningMessages.hour):00.")
                }

                Section {
                    if app.isPlus {
                        Label("Fate+ is on", systemImage: "sparkles")
                        if Store.mockPurchases {
                            Button("Turn off Fate+ (test build)") { app.resetPlusForTesting() }
                        } else {
                            Button("Manage subscription") { manageSubscription = true }
                        }
                    } else {
                        Text("\(app.freeMessagesLeft) of \(AppState.freeMessagesPerDay) free messages left today")
                        Button("Get Fate+") { showPaywall = true }
                        if !Store.mockPurchases {
                            Button(restoring ? "Restoring…" : "Restore purchases") { Task { await restore() } }
                                .disabled(restoring)
                        }
                    }
                    #if DEBUG
                    Button("Debug: reset Fate+ and free messages") { app.resetPlusForTesting() }
                    #endif
                } header: {
                    Text("Fate+")
                } footer: {
                    if Store.mockPurchases {
                        Text("Test build: Fate+ is free to try and nothing is charged.")
                    }
                }

                Section {
                    Button("Replay onboarding") {
                        dismiss()
                        app.replayOnboarding()
                    }
                    #if DEBUG
                    Button("Debug: pretend a day has passed") { app.ageReadingsByOneDay() }
                    #endif
                }

                Section {
                    Button("Delete all readings", role: .destructive) { confirmClear = true }
                        .confirmationDialog("Delete all saved readings? This can't be undone.", isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("Delete readings", role: .destructive) { app.clearReadings() }
                        }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("As Fate Would Have It is for entertainment only. Its psychics are AI characters and can't predict the future.")
                        Text("Planet textures: [Solar System Scope](https://www.solarsystemscope.com/textures/), based on NASA imagery, CC BY 4.0.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .manageSubscriptionsSheet(isPresented: $manageSubscription)
            .alert("Fate+", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(psychic: app.matchedPsychic, goal: app.onboardingGoal,
                            name: app.userName.trimmingCharacters(in: .whitespaces), source: "settings") { showPaywall = false }
            }
        }
        .preferredColorScheme(.light)
    }

    private func restore() async {
        Analytics.track(.paywallRestoreTapped, ["source": "settings"])
        restoring = true
        defer { restoring = false }
        switch await store.restore() {
        case .restored:
            Analytics.track(.restored, ["source": "settings", "found": "true"])
            restoreMessage = "Fate+ is back on. Welcome back."
        case .nothingFound:
            Analytics.track(.restored, ["source": "settings", "found": "false"])
            restoreMessage = "No Fate+ subscription was found for this Apple Account."
        case .cancelled:
            break
        case .failed(let reason):
            Analytics.track(.restored, ["source": "settings", "found": "false", "reason": reason])
            restoreMessage = "Purchases couldn't be restored. Check your connection and try again."
        }
    }
}
