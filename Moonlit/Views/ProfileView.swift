import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    let psychic: Psychic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(spacing: 10) {
                    AvatarView(psychic: psychic, size: 150)
                        .padding(6)
                        .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
                    Text(psychic.name)
                        .font(Theme.display(36))
                        .foregroundStyle(Theme.textBright)
                        .padding(.top, 6)
                    Text(psychic.specialty).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.gold)
                    HStack(spacing: 6) { OnlineDot(); Text("Available now") }
                        .font(.system(size: 13)).foregroundStyle(Theme.online)
                    HStack(spacing: 8) { ForEach(psychic.styles, id: \.self) { Pill(text: $0) } }
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    EyebrowText("About")
                    Text(psychic.bio).font(.system(size: 16)).foregroundStyle(Theme.text).lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    EyebrowText("A taste of a reading")
                    Text("“\(psychic.general[0])”")
                        .font(Theme.display(21, .regular).italic())
                        .foregroundStyle(Theme.textBright)
                        .lineSpacing(2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(strong: true)

                VStack(alignment: .leading, spacing: 10) {
                    EyebrowText("Ask \(psychic.short) about")
                    ForEach(psychic.asks, id: \.self) { q in
                        Button { app.openChat(psychic, asking: q) } label: {
                            HStack {
                                Text(q).font(.system(size: 16)).foregroundStyle(Theme.text)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(Theme.gold)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .cardSurface()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            Button("Start a reading with \(psychic.short)") { app.openChat(psychic) }
                .buttonStyle(GoldButtonStyle())
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .background(Theme.bg)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }
}
