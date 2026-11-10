import SwiftUI
import UIKit

struct AvatarView: View {
    let psychic: Psychic
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let image = UIImage(named: psychic.imageName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.surfaceRaised
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(hex: psychic.ringHex), lineWidth: size > 80 ? 2 : 1.5))
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.system(size: size * 0.7, weight: .regular))
            Text("Moonlit").font(Theme.display(size))
        }
        .foregroundStyle(Theme.gold)
        .accessibilityElement(children: .combine)
    }
}

struct MiniTarotCard: View {
    var numeral: String?
    var width: CGFloat = 48

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "sparkle").font(.system(size: width * 0.38))
            if let numeral, !numeral.isEmpty {
                Text(numeral).font(Theme.display(width * 0.28))
            }
        }
        .foregroundStyle(Theme.gold)
        .frame(width: width, height: width * 1.5)
        .background(Theme.cardFace, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.gold, lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

struct TypingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.lilac)
                        .frame(width: 7, height: 7)
                        .opacity(i == step ? 1 : 0.3)
                }
            }
        }
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSoft)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}
