import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var checking = false

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
                    Button("Use local server") { app.serverURL = ReadingClient.defaultServerURL }
                } header: {
                    Text("Reading server")
                } footer: {
                    Text("Readings come from the Moonlit server, which holds the Claude API key. Leave the address empty for demo mode.")
                }

                Section("You") {
                    TextField("First name", text: $app.userName)
                    Picker("Star sign", selection: Binding(get: { app.sign ?? "" }, set: { app.sign = $0.isEmpty ? nil : $0 })) {
                        Text("Not set").tag("")
                        ForEach(Catalog.signs) { Text($0.name).tag($0.name) }
                    }
                }

                Section {
                    Button("Delete all readings", role: .destructive) { confirmClear = true }
                        .confirmationDialog("Delete all saved readings? This can't be undone.", isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("Delete readings", role: .destructive) { app.clearReadings() }
                        }
                } footer: {
                    Text("Moonlit is for entertainment only. Its psychics are AI characters and can't predict the future.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
