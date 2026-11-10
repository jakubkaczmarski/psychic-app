import SwiftUI

@main
struct MoonlitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                // Tapping a morning message opens your psychic with today's card.
                .onReceive(NotificationCenter.default.publisher(for: .openDailyCard)) { _ in
                    app.askAboutDailyCard()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Keep a week of morning messages queued up.
            if phase == .active { app.refreshMorningMessages() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if app.onboarded {
                NavigationStack(path: $app.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .profile(let id): ProfileView(psychic: Catalog.psychic(id))
                            case .chat(let id): ChatView(psychic: Catalog.psychic(id))
                            case .readings: ReadingsView()
                            }
                        }
                }
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.onboarded)
    }
}
