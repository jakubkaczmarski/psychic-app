import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: -14) {
                        ForEach(Catalog.psychics) { p in
                            AvatarView(psychic: p, size: 62)
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                        }
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Wordmark(size: 22)
                        Text("Meet your\npsychic circle.")
                            .font(Theme.display(42, .medium))
                            .foregroundStyle(Theme.textBright)
                        Text("Five AI psychics, one for every kind of question. Tell them a little about yourself so the readings feel personal.")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should they call you?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSoft)
                        TextField("", text: $app.userName, prompt: Text("Your first name").foregroundColor(Theme.faint))
                            .textContentType(.givenName)
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderStrong, lineWidth: 1))
                            .foregroundStyle(Theme.textBright)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your star sign")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSoft)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Catalog.signs) { s in
                                let selected = app.sign == s.name
                                Button {
                                    app.sign = selected ? nil : s.name
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(s.name).font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Theme.textBright)
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                        Text(s.dates).font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .background(selected ? Color(hex: 0x2A2350) : Theme.surface,
                                                in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(selected ? Theme.gold : Theme.border, lineWidth: selected ? 1.5 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 4) {
                Button("Enter the circle") { enter() }
                    .buttonStyle(GoldButtonStyle())
                Button("Skip for now") { enter() }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .background(Theme.bg)
        }
        .background(Theme.bg)
    }

    private func enter() {
        nameFocused = false
        app.onboarded = true
    }
}
