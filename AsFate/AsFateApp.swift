import SwiftUI

@main
struct AsFateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    init() { Analytics.start() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                // Fate+ follows the App Store's verified subscriptions, checked at launch and on every change.
                .task { [app] in store.start { app.setPlusEntitlement($0) } }
                .preferredColorScheme(.light)
                .tint(Theme.gold)
                // Tapping a morning message opens your psychic with today's card.
                .onReceive(NotificationCenter.default.publisher(for: .openDailyCard)) { _ in
                    app.askAboutDailyCard()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Keep a week of morning messages queued up.
            if phase == .active {
                app.refreshMorningMessages()
                app.syncPhotos()
                Analytics.appBecameActive()
            }
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
