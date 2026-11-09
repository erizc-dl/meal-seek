//
//  RecipeSymbol.swift
//  Meal Seek
//
//  A procedurally generated recipe tile: flat orange-family shapes derived at
//  render time from the recipe's stable id, with the fixed meal-type glyph
//  centered on top. Nothing is stored — same id, same symbol, every launch.
//

import SwiftUI

struct RecipeSymbol: View {
    let recipe: Recipe
    /// Edge length in points. Corner radius and shape geometry scale with it
    /// (46 matches the meal-card icon tile, larger sizes suit hero use).
    let size: CGFloat

    var body: some View {
        let seed = Self.stableSeed(recipe.id)
        let scheme = Self.schemes[Int(seed & 3)]
        let motifIndex = Int((seed >> 8) & 3)
        let mirrored = (seed >> 16) & 1 == 1

        ZStack {
            scheme.base
            motif(motifIndex, color: scheme.motif)
                .scaleEffect(x: mirrored ? -1 : 1)
            Image(systemName: Self.glyphName(for: recipe.mealTypes.first))
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(scheme.glyph)
        }
        .frame(width: size, height: size)
        // Same radius-to-size ratio as the 46pt meal-card tile (radius 13).
        .clipShape(RoundedRectangle(cornerRadius: size * 13 / 46))
    }

    // MARK: Seed

    /// FNV-1a over the id's UTF-8 bytes. Deliberately not `String.hashValue`,
    /// which is randomized per process and would reshuffle symbols on launch.
    static func stableSeed(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: Color schemes (bits 0–1 of the seed)

    private struct Scheme {
        let base: Color
        let motif: Color
        let glyph: Color
    }

    /// Flat three-orange combinations. Motifs stay out of the tile's center,
    /// so each glyph color only ever needs to contrast with its base.
    private static let schemes: [Scheme] = [
        Scheme(base: .brandOrangePale, motif: .brandOrangeMid, glyph: .brandOrange),
        Scheme(base: .brandOrange, motif: .brandOrangeMid, glyph: .backgroundPrimary),
        Scheme(base: .brandOrangeMid, motif: .brandOrange, glyph: .backgroundPrimary),
        Scheme(base: .brandOrangePale, motif: .backgroundPrimary, glyph: .brandOrange),
    ]

    // MARK: Motifs (bits 8–9; bit 16 mirrors horizontally)

    @ViewBuilder
    private func motif(_ index: Int, color: Color) -> some View {
        switch index {
        case 0: // large circle overflowing the top-leading corner
            Circle()
                .fill(color)
                .frame(width: size * 0.85, height: size * 0.85)
                .position(x: size * 0.18, y: size * 0.15)
        case 1: // wedge filling the bottom-leading corner
            CornerWedge()
                .fill(color)
        case 2: // low arch rising from the bottom edge
            Circle()
                .fill(color)
                .frame(width: size * 1.15, height: size * 1.15)
                .position(x: size * 0.5, y: size * 1.25)
        default: // a small dot tucked into each corner
            let inset = size * 0.16
            ForEach(0..<4, id: \.self) { corner in
                Circle()
                    .fill(color)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .position(
                        x: corner % 2 == 0 ? inset : size - inset,
                        y: corner < 2 ? inset : size - inset
                    )
            }
        }
    }

    private struct CornerWedge: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.45))
            path.closeSubpath()
            return path
        }
    }

    // MARK: Meal-type glyph (fixed per meal type, never randomized)

    private static func glyphName(for mealType: String?) -> String {
        switch mealType {
        case "breakfast": return "fork.knife"
        case "lunch": return "leaf"
        case "dinner": return "flame"
        default: return "fork.knife"
        }
    }
}

// MARK: - Preview

/// Eyeball check: variety across ids, determinism within one id, both sizes.
#Preview("RecipeSymbol variety") {
    let samples: [(id: String, mealType: String)] = [
        ("garlic-butter-shrimp-pasta", "dinner"),
        ("veggie-scramble-breakfast-tacos", "breakfast"),
        ("chicken-teriyaki-rice-bowl", "dinner"),
        ("spinach-ricotta-frittata", "breakfast"),
        ("tuscan-white-bean-soup", "lunch"),
        ("lemon-ricotta-pancake", "breakfast"),
        ("tomato-mozzarella-breakfast-bruschetta", "breakfast"),
        ("italian-sausage-breakfast-skillet", "dinner"),
    ]

    ScrollView {
        VStack(spacing: 16) {
            ForEach(samples, id: \.id) { sample in
                let recipe = Recipe(
                    id: sample.id,
                    name: sample.id,
                    cuisine: "Italian",
                    regions: [],
                    mealTypes: [sample.mealType],
                    tags: [],
                    allergens: [],
                    baseServings: 4,
                    prepTimeMinutes: 10,
                    cookTimeMinutes: 20,
                    ingredients: [],
                    instructions: [],
                    nutrition: Nutrition(calories: nil, protein: nil, carbs: nil, fat: nil)
                )
                HStack(spacing: 16) {
                    RecipeSymbol(recipe: recipe, size: 120)
                    RecipeSymbol(recipe: recipe, size: 46)
                    Spacer()
                }
            }
        }
        .padding(20)
    }
    .background(Color.backgroundPrimary)
}
