import SwiftUI

/// The window background, in the spirit of a DMG installer backdrop: a soft
/// mesh gradient with a faint pixel plank texture, a nod to a crafting table.
struct CraftingBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: scheme == .dark ? Self.dark : Self.light)
            PlankTexture()
                .opacity(scheme == .dark ? 0.55 : 0.4)
                .blendMode(scheme == .dark ? .plusLighter : .multiply)
        }
        .ignoresSafeArea()
    }

    private static let light: [Color] = [
        Color(red: 0.97, green: 0.90, blue: 0.82), Color(red: 0.93, green: 0.88, blue: 0.96), Color(red: 0.84, green: 0.91, blue: 0.97),
        Color(red: 0.95, green: 0.86, blue: 0.78), Color(red: 0.92, green: 0.90, blue: 0.97), Color(red: 0.81, green: 0.90, blue: 0.94),
        Color(red: 0.91, green: 0.82, blue: 0.73), Color(red: 0.87, green: 0.85, blue: 0.95), Color(red: 0.78, green: 0.88, blue: 0.92),
    ]

    private static let dark: [Color] = [
        Color(red: 0.16, green: 0.12, blue: 0.13), Color(red: 0.14, green: 0.12, blue: 0.22), Color(red: 0.07, green: 0.14, blue: 0.22),
        Color(red: 0.19, green: 0.13, blue: 0.12), Color(red: 0.12, green: 0.12, blue: 0.20), Color(red: 0.06, green: 0.15, blue: 0.19),
        Color(red: 0.20, green: 0.14, blue: 0.11), Color(red: 0.11, green: 0.11, blue: 0.17), Color(red: 0.05, green: 0.13, blue: 0.16),
    ]
}

/// Pixel-art wood planks: rows of cells with deterministic grain noise.
private struct PlankTexture: View {
    var cell: CGFloat = 12

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            for y in 0..<rows {
                // planks are 4 cells tall, each plank shifted horizontally
                let plank = y / 4
                for x in 0..<cols {
                    let n = noise(x + plank * 7, y)
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(.brown.opacity(0.02 + n * 0.07)))
                }
                if y % 4 == 0 {
                    let line = CGRect(x: 0, y: CGFloat(y) * cell, width: size.width, height: 1)
                    ctx.fill(Path(line), with: .color(.brown.opacity(0.10)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func noise(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double(h & 0xFF) / 255
    }
}
