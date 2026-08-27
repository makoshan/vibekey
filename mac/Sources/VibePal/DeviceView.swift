import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The aluminium VibePal body: mic grille, dial, mic / confirm / cancel keys.
/// `glow` tints the dial when an agent state is active.
struct DeviceView: View {
    var glow: Color? = nil
    private let w: CGFloat = 132, h: CGFloat = 412

    var body: some View {
        ZStack(alignment: .top) {
            if let glow {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.45), glow.opacity(0.04), .clear],
                                         center: .center, startRadius: 8, endRadius: 150))
                    .frame(width: 300, height: 300)
                    .offset(y: 4)
            }

            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(hex: 0xFDFDFE), Color(hex: 0xE9EAEC), Color(hex: 0xD4D5D9)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color(hex: 0xC9CACD), lineWidth: 1))
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)

            grille.offset(y: 24)
            Text("VibePal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x8C8D91))
                .offset(y: 66)

            dial.offset(y: 96)
            key(.mic).offset(y: 223)
            key(.check).offset(y: 289)
            key(.cross).offset(y: 355)

            // side button
            RoundedRectangle(cornerRadius: 4.5)
                .fill(Color(hex: 0xDBDCDF))
                .overlay(RoundedRectangle(cornerRadius: 4.5).stroke(Color(hex: 0xC6C7CB)))
                .frame(width: 9, height: 34)
                .offset(x: w / 2 + 3, y: 144)
        }
        .frame(width: 200, height: h + 12)
    }

    private var grille: some View {
        HStack(spacing: 7) {
            ForEach([22, 30, 34, 30, 22], id: \.self) { hh in
                Capsule().fill(Color(hex: 0xB6B7BB)).frame(width: 3, height: CGFloat(hh))
            }
        }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .fill(glow == nil
                      ? AnyShapeStyle(RadialGradient(colors: [.white, Color(hex: 0xE3E4E8)],
                                                     center: UnitPoint(x: 0.38, y: 0.32), startRadius: 4, endRadius: 70))
                      : AnyShapeStyle(RadialGradient(colors: [(glow ?? .green).opacity(0.85), glow ?? .green],
                                                     center: UnitPoint(x: 0.4, y: 0.34), startRadius: 4, endRadius: 70)))
                .overlay(Circle().stroke(glow?.opacity(0.7) ?? Color(hex: 0xCFD0D4), lineWidth: 1.5))
                .frame(width: 112, height: 112)
                .shadow(color: (glow ?? .clear).opacity(0.55), radius: 18)

            ForEach(0..<4) { i in
                Capsule()
                    .fill(Color(hex: 0xB9BABE))
                    .frame(width: 2.5, height: 10)
                    .offset(y: -51)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            Circle()
                .fill(glow?.opacity(0.75) ?? Color(hex: 0xEDEEF0))
                .overlay(Circle().stroke(Color(hex: 0xDCDDE0).opacity(glow == nil ? 1 : 0)))
                .frame(width: 40, height: 40)
        }
    }

    private enum Key { case mic, check, cross }

    private func key(_ k: Key) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .overlay(Circle().stroke(Color(hex: 0xE2E3E6), lineWidth: 1.4))
                .frame(width: 54, height: 54)
            Image(systemName: {
                switch k {
                case .mic: return "mic"
                case .check: return "checkmark"
                case .cross: return "xmark"
                }
            }())
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color(hex: 0x7C7D82))
        }
    }
}
