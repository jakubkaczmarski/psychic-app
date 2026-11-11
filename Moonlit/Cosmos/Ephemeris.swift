import Foundation

/// Where the planets are on a given date, worked out on the phone.
///
/// Planets use NASA JPL's "Approximate Positions of the Planets" (Keplerian elements, valid 1800–2050,
/// accurate to well under a degree), which is plenty for showing which zodiac sign a planet is in.
/// The Moon uses a short series that is good to about a degree.
enum Ephemeris {
    struct Vec3 { var x, y, z: Double }

    enum Body: String, CaseIterable, Identifiable {
        case sun, moon, mercury, venus, earth, mars, jupiter, saturn, uranus, neptune
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
    }

    /// A body as seen from Earth: what astrology reads.
    struct Placement: Identifiable {
        let body: Body
        /// Ecliptic longitude seen from Earth, 0–360°, 0 = start of Aries.
        let longitude: Double
        let retrograde: Bool
        var id: String { body.id }
        var sign: ZodiacSign { ZodiacSign.all[Int(longitude / 30) % 12] }
        var degreeInSign: Int { Int(longitude.truncatingRemainder(dividingBy: 30)) }
    }

    // MARK: Time

    /// Days since J2000.0 (1 Jan 2000, 12:00 TT).
    static func daysSinceJ2000(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
    }

    // MARK: Orbital elements (JPL table 1)

    private struct Elements {
        // a (AU), e, I, L, long. perihelion, long. ascending node (degrees), then rates per century.
        let a, e, i, l, peri, node: Double
        let da, de, di, dl, dperi, dnode: Double
    }

    private static let elements: [Body: Elements] = [
        .mercury: .init(a: 0.38709927, e: 0.20563593, i: 7.00497902, l: 252.25032350, peri: 77.45779628, node: 48.33076593,
                        da: 0.00000037, de: 0.00001906, di: -0.00594749, dl: 149472.67411175, dperi: 0.16047689, dnode: -0.12534081),
        .venus: .init(a: 0.72333566, e: 0.00677672, i: 3.39467605, l: 181.97909950, peri: 131.60246718, node: 76.67984255,
                      da: 0.00000390, de: -0.00004107, di: -0.00078890, dl: 58517.81538729, dperi: 0.00268329, dnode: -0.27769418),
        .earth: .init(a: 1.00000261, e: 0.01671123, i: -0.00001531, l: 100.46457166, peri: 102.93768193, node: 0,
                      da: 0.00000562, de: -0.00004392, di: -0.01294668, dl: 35999.37244981, dperi: 0.32327364, dnode: 0),
        .mars: .init(a: 1.52371034, e: 0.09339410, i: 1.84969142, l: -4.55343205, peri: -23.94362959, node: 49.55953891,
                     da: 0.00001847, de: 0.00007882, di: -0.00813131, dl: 19140.30268499, dperi: 0.44441088, dnode: -0.29257343),
        .jupiter: .init(a: 5.20288700, e: 0.04838624, i: 1.30439695, l: 34.39644051, peri: 14.72847983, node: 100.47390909,
                        da: -0.00011607, de: -0.00013253, di: -0.00183714, dl: 3034.74612775, dperi: 0.21252668, dnode: 0.20469106),
        .saturn: .init(a: 9.53667594, e: 0.05386179, i: 2.48599187, l: 49.95424423, peri: 92.59887831, node: 113.66242448,
                       da: -0.00125060, de: -0.00050991, di: 0.00193609, dl: 1222.49362201, dperi: -0.41897216, dnode: -0.28867794),
        .uranus: .init(a: 19.18916464, e: 0.04725744, i: 0.77263783, l: 313.23810451, peri: 170.95427630, node: 74.01692503,
                       da: -0.00196176, de: -0.00004397, di: -0.00242939, dl: 428.48202785, dperi: 0.40805281, dnode: 0.04240589),
        .neptune: .init(a: 30.06992276, e: 0.00859048, i: 1.77004347, l: -55.12002969, peri: 44.96476227, node: 131.78422574,
                        da: 0.00026291, de: 0.00005105, di: 0.00035372, dl: 218.45945325, dperi: -0.32241464, dnode: -0.00508664),
    ]

    /// The planets that orbit the Sun, in order.
    static let planets: [Body] = [.mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune]

    static func semiMajorAxis(_ body: Body) -> Double { elements[body]?.a ?? 1 }

    // MARK: Positions

    /// Position around the Sun in AU, ecliptic coordinates (x toward the start of Aries, z toward the ecliptic north pole).
    static func heliocentric(_ body: Body, days d: Double) -> Vec3 {
        guard let el = elements[body] else { return Vec3(x: 0, y: 0, z: 0) }
        let t = d / 36_525
        let e = el.e + el.de * t
        let meanLongitude = el.l + el.dl * t
        let peri = el.peri + el.dperi * t
        let node = el.node + el.dnode * t
        return orbitPoint(a: el.a + el.da * t, e: e, i: el.i + el.di * t,
                          meanAnomaly: meanLongitude - peri, argPeri: peri - node, node: node)
    }

    /// Points along a body's current orbit, for drawing it.
    static func orbit(_ body: Body, days d: Double, samples: Int = 180) -> [Vec3] {
        guard let el = elements[body] else { return [] }
        let t = d / 36_525
        let peri = el.peri + el.dperi * t, node = el.node + el.dnode * t
        return (0...samples).map { k in
            orbitPoint(a: el.a + el.da * t, e: el.e + el.de * t, i: el.i + el.di * t,
                       meanAnomaly: Double(k) / Double(samples) * 360, argPeri: peri - node, node: node)
        }
    }

    private static func orbitPoint(a: Double, e: Double, i: Double, meanAnomaly: Double, argPeri: Double, node: Double) -> Vec3 {
        let rad = Double.pi / 180
        var m = meanAnomaly.truncatingRemainder(dividingBy: 360)
        if m > 180 { m -= 360 } else if m < -180 { m += 360 }
        let mr = m * rad
        // Kepler's equation, Newton's method.
        var ecc = mr + e * sin(mr)
        for _ in 0..<8 { ecc -= (ecc - e * sin(ecc) - mr) / (1 - e * cos(ecc)) }
        let xp = a * (cos(ecc) - e), yp = a * sqrt(1 - e * e) * sin(ecc)
        let w = argPeri * rad, o = node * rad, inc = i * rad
        let x = (cos(w) * cos(o) - sin(w) * sin(o) * cos(inc)) * xp + (-sin(w) * cos(o) - cos(w) * sin(o) * cos(inc)) * yp
        let y = (cos(w) * sin(o) + sin(w) * cos(o) * cos(inc)) * xp + (-sin(w) * sin(o) + cos(w) * cos(o) * cos(inc)) * yp
        let z = (sin(w) * sin(inc)) * xp + (cos(w) * sin(inc)) * yp
        return Vec3(x: x, y: y, z: z)
    }

    /// The Moon's ecliptic longitude seen from Earth, in degrees.
    static func moonLongitude(days d: Double) -> Double {
        let rad = Double.pi / 180
        let l = 218.316 + 13.176396 * d          // mean longitude
        let m = (134.963 + 13.064993 * d) * rad  // Moon's mean anomaly
        let ms = (357.529 + 0.98560028 * d) * rad // Sun's mean anomaly
        let dd = (297.850 + 12.190749 * d) * rad // mean elongation
        let lon = l + 6.289 * sin(m) + 1.274 * sin(2 * dd - m) + 0.658 * sin(2 * dd)
            + 0.214 * sin(2 * m) - 0.186 * sin(ms)
        return normalize(lon)
    }

    /// Ecliptic longitude of a body seen from Earth, in degrees.
    static func geocentricLongitude(_ body: Body, days d: Double) -> Double {
        switch body {
        case .moon: return moonLongitude(days: d)
        case .earth: return 0
        case .sun:
            let e = heliocentric(.earth, days: d)
            return normalize(atan2(-e.y, -e.x) * 180 / .pi)
        default:
            let p = heliocentric(body, days: d), e = heliocentric(.earth, days: d)
            return normalize(atan2(p.y - e.y, p.x - e.x) * 180 / .pi)
        }
    }

    /// Everything astrology reads on that date, in the usual order.
    static func placements(on date: Date) -> [Placement] {
        let d = daysSinceJ2000(date)
        let bodies: [Body] = [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]
        return bodies.map { body in
            let now = geocentricLongitude(body, days: d)
            // Retrograde: moving backwards through the zodiac, seen from Earth.
            let retro = body != .sun && body != .moon && dailyMotion(body, days: d) < 0
            return Placement(body: body, longitude: now, retrograde: retro)
        }
    }

    /// Apparent motion through the zodiac in degrees per day; negative means retrograde.
    static func dailyMotion(_ body: Body, days d: Double) -> Double {
        var step = geocentricLongitude(body, days: d + 0.5) - geocentricLongitude(body, days: d - 0.5)
        if step > 180 { step -= 360 } else if step < -180 { step += 360 }
        return step
    }

    /// The retrograde stretch happening at `d`, or the next one. Days since J2000, to the nearest day.
    static func retrogradePeriod(_ body: Body, near d: Double) -> (start: Double, end: Double)? {
        guard ![.sun, .moon, .earth].contains(body) else { return nil }
        var t = d.rounded(.down)
        if dailyMotion(body, days: t) < 0 {
            var start = t
            while dailyMotion(body, days: start - 1) < 0, d - start < 250 { start -= 1 }
            var end = t
            while dailyMotion(body, days: end + 1) < 0, end - d < 250 { end += 1 }
            return (start, end)
        }
        while dailyMotion(body, days: t) >= 0 {
            t += 1
            if t - d > 420 { return nil }
        }
        var end = t
        while dailyMotion(body, days: end + 1) < 0, end - t < 250 { end += 1 }
        return (t, end)
    }

    /// The calendar date for a day count since J2000.
    static func date(days d: Double) -> Date {
        Date(timeIntervalSince1970: 946_728_000 + d * 86_400)
    }

    static func normalize(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

struct ZodiacSign: Identifiable, Hashable {
    let name: String
    let glyph: String
    /// A few words for "Venus in Libra" style lines.
    let flavour: String
    var id: String { name }

    static let all: [ZodiacSign] = [
        .init(name: "Aries", glyph: "♈\u{FE0E}", flavour: "bold and impatient"),
        .init(name: "Taurus", glyph: "♉\u{FE0E}", flavour: "steady and comfort-loving"),
        .init(name: "Gemini", glyph: "♊\u{FE0E}", flavour: "curious and chatty"),
        .init(name: "Cancer", glyph: "♋\u{FE0E}", flavour: "tender and protective"),
        .init(name: "Leo", glyph: "♌\u{FE0E}", flavour: "warm and dramatic"),
        .init(name: "Virgo", glyph: "♍\u{FE0E}", flavour: "precise and helpful"),
        .init(name: "Libra", glyph: "♎\u{FE0E}", flavour: "charming and fair-minded"),
        .init(name: "Scorpio", glyph: "♏\u{FE0E}", flavour: "intense and private"),
        .init(name: "Sagittarius", glyph: "♐\u{FE0E}", flavour: "restless and hopeful"),
        .init(name: "Capricorn", glyph: "♑\u{FE0E}", flavour: "ambitious and patient"),
        .init(name: "Aquarius", glyph: "♒\u{FE0E}", flavour: "independent and unusual"),
        .init(name: "Pisces", glyph: "♓\u{FE0E}", flavour: "dreamy and intuitive"),
    ]
}

extension Ephemeris.Body {
    var glyph: String {
        switch self {
        case .sun: "☉"
        case .moon: "☽"
        case .mercury: "☿"
        case .venus: "♀"
        case .earth: "⊕"
        case .mars: "♂"
        case .jupiter: "♃"
        case .saturn: "♄"
        case .uranus: "♅"
        case .neptune: "♆"
        }
    }

    /// What the body rules in astrology, for the detail card.
    var rules: String {
        switch self {
        case .sun: "who you are at your core"
        case .moon: "your moods and needs"
        case .mercury: "how you think and talk"
        case .venus: "love, beauty and money"
        case .earth: "home: where you're looking from"
        case .mars: "drive, desire and anger"
        case .jupiter: "luck and growth"
        case .saturn: "discipline and hard lessons"
        case .uranus: "sudden change"
        case .neptune: "dreams and illusions"
        }
    }

    /// Display colour as RGB hex.
    var colorHex: UInt32 {
        switch self {
        case .sun: 0xFFD27A
        case .moon: 0xE6E2F0
        case .mercury: 0xB8B2A8
        case .venus: 0xF2D6A2
        case .earth: 0x5FA8E8
        case .mars: 0xE0704A
        case .jupiter: 0xD9B48A
        case .saturn: 0xE8D49A
        case .uranus: 0x8FE0E0
        case .neptune: 0x5B7FE8
        }
    }
}
