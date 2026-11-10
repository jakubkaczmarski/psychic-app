import SwiftUI

@main
struct MoonlitApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
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
