import SwiftUI

/// Cards on the table after one turn of a reading: the cards turned so far face up, the rest face down,
/// and the card just turned picked out with its position and meaning.
struct SpreadView: View {
    let spread: CardSpread
    @State private var flipped = false

    private var newest: DrawnCard? { spread.cards.last }
    private var single: Bool { spread.positions.count == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: single ? 14 : 6) {
                ForEach(spread.positions.indices, id: \.self) { i in
                    slot(i)
                }
                if single, let card = newest { title(card) }
            }
            if !single, let card = newest { title(card) }
            if let card = newest {
                Text(card.meaning)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !spread.isComplete {
                Text(spread.cards.count == 1 && spread.positions.count > 1
                     ? "Reply when you're ready, and the next card turns."
                     : "\(spread.positions.count - spread.cards.count) still face down.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.gold, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.15)) { flipped = true } }
    }

    private var cardWidth: CGFloat {
        switch spread.positions.count {
        case 1: 64
        case 2...3: 64
        default: 44
        }
    }

    @ViewBuilder private func slot(_ i: Int) -> some View {
        let isNewest = i == spread.cards.count - 1
        Group {
            if i < spread.cards.count {
                let card = spread.cards[i]
                // The card just turned flips over; earlier ones are already face up.
                ZStack {
                    CardBack().opacity(isNewest && !flipped ? 1 : 0)
                    CardFace(card: card, playing: spread.isPlaying)
                        .opacity(isNewest && !flipped ? 0 : 1)
                        .rotationEffect(.degrees(card.reversed ? 180 : 0))
                }
                .rotation3DEffect(.degrees(isNewest && !flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            } else {
                CardBack()
            }
        }
        .frame(width: cardWidth, height: cardWidth / TarotArt.aspect)
        .overlay(
            RoundedRectangle(cornerRadius: cardWidth * 0.06, style: .continuous)
                .stroke(Theme.gold, lineWidth: isNewest && !single ? 2 : 0)
        )
        .opacity(i < spread.cards.count && !isNewest ? 0.75 : 1)
    }

    private func title(_ card: DrawnCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowText(single ? "Your card" : "\(card.position) · \(spread.cards.count) of \(spread.positions.count)")
            Text(card.name)
                .font(Theme.display(single ? 24 : 22))
                .foregroundStyle(Theme.gold)
                .fixedSize(horizontal: false, vertical: true)
            if card.reversed {
                Text("Reversed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var accessibilityText: String {
        guard let card = newest else { return spread.name }
        let reversed = card.reversed ? ", reversed" : ""
        let place = single ? "Your card" : "\(card.position), card \(spread.cards.count) of \(spread.positions.count)"
        return "\(place): \(card.name)\(reversed). \(card.meaning)"
    }
}

/// The face of a drawn card: tarot art, or a simple playing card.
private struct CardFace: View {
    let card: DrawnCard
    let playing: Bool

    var body: some View {
        if playing {
            PlayingCardFace(card: card)
        } else {
            TarotArt(card: card.tarotCard, compact: true)
        }
    }
}

/// A plain playing card: rank in the corners, the suit in the middle.
struct PlayingCardFace: View {
    let card: DrawnCard

    private var red: Bool { card.suit == "Hearts" || card.suit == "Diamonds" }
    private var symbol: String {
        switch card.suit {
        case "Hearts": "suit.heart.fill"
        case "Diamonds": "suit.diamond.fill"
        case "Clubs": "suit.club.fill"
        default: "suit.spade.fill"
        }
    }
    private var rank: String {
        switch card.rank {
        case "Ace": "A"
        case "Jack": "J"
        case "Queen": "Q"
        case "King": "K"
        default: ["Two": "2", "Three": "3", "Four": "4", "Five": "5", "Six": "6", "Seven": "7",
                  "Eight": "8", "Nine": "9", "Ten": "10"][card.rank] ?? card.rank
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let ink = red ? Color(hex: 0xB0302A) : Color(hex: 0x1E140C)
            let shape = RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
            ZStack {
                shape.fill(Color(hex: 0xFFFBF2))
                shape.stroke(Color(hex: 0xD2BF99), lineWidth: max(0.6, w * 0.015))
                Image(systemName: symbol)
                    .font(.system(size: w * 0.42))
                    .foregroundStyle(ink)
                VStack(spacing: 0) {
                    Text(rank).font(.system(size: w * 0.24, weight: .bold, design: .serif))
                    Image(systemName: symbol).font(.system(size: w * 0.16))
                }
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(w * 0.07)
            }
        }
    }
}

/// The back of a card, for cards still face down.
struct CardBack: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shape = RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
            ZStack {
                shape.fill(Color(hex: 0x3A2418))
                RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                    .stroke(Color(hex: 0xD4AF6A).opacity(0.7), lineWidth: max(0.6, w * 0.02))
                    .padding(w * 0.08)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: w * 0.32))
                    .foregroundStyle(Color(hex: 0xD4AF6A).opacity(0.85))
            }
        }
    }
}
