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
        // The name is long: it shrinks to fit beside the header buttons.
        Text("As Fate Would Have It")
            .font(Theme.display(size))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Theme.gold)
    }
}

/// A small face-up card, found by its numeral.
struct MiniTarotCard: View {
    var numeral: String?
    var width: CGFloat = 48

    var body: some View {
        Group {
            if let card = Catalog.deck.first(where: { $0.numeral == numeral }) {
                TarotArt(card: card, compact: true)
            } else {
                TarotBack()
            }
        }
        .frame(width: width, height: width / TarotArt.aspect)
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
            .background(Theme.surfaceRaised, in: Theme.chip)
            .overlay(Theme.chip.stroke(Theme.border, lineWidth: 1))
    }
}
