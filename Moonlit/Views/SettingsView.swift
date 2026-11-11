import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var checking = false
    @State private var notificationsBlocked = false
    @State private var showPaywall = false

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
                    Text("Readings come from the Moonlit server. Leave the address empty for demo mode.")
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
                         ? "Notifications are turned off for Moonlit. You can allow them in the iPhone Settings app."
                         : "Your psychic reads your card of the day and sends a message at \(MorningMessages.hour):00.")
                }

                Section {
                    if app.isPlus {
                        Label("Moonlit+ is on", systemImage: "sparkles")
                    } else {
                        Text("\(app.freeMessagesLeft) of \(AppState.freeMessagesPerDay) free messages left today")
                        Button("Get Moonlit+") { showPaywall = true }
                    }
                    #if DEBUG
                    Button("Debug: reset Moonlit+ and free messages") { app.resetPlusForTesting() }
                    #endif
                } header: {
                    Text("Moonlit+")
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
                        Text("Moonlit is for entertainment only. Its psychics are AI characters and can't predict the future.")
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
            .sheet(isPresented: $showPaywall) {
                PaywallView(psychic: app.matchedPsychic, goal: app.onboardingGoal,
                            name: app.userName.trimmingCharacters(in: .whitespaces), source: "settings") { showPaywall = false }
            }
        }
        .preferredColorScheme(.dark)
    }
}
