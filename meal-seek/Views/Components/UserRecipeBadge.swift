//
//  UserRecipeBadge.swift
//  Meal Seek
//
//  The mark that says "you wrote this one". Deliberately small: a user recipe
//  sits in the library as a peer of the built-ins, so it gets a corner glyph
//  rather than a label competing with the recipe's own name.
//
//  Uses the same pale-orange-on-white treatment as every other badge in the
//  app — no new hue, nothing that reads as a warning.
//

import SwiftUI

struct UserRecipeBadge: View {
    /// Edge length of the circular badge. 18 sits over a 46pt symbol tile;
    /// 26 suits the 160pt detail hero.
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.textOnPale)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.brandOrangePale))
            .overlay(Circle().stroke(Color.backgroundCard, lineWidth: 1.5))
            .accessibilityLabel("Your recipe")
    }
}

extension View {
    /// Pins the badge to the symbol tile's top-trailing corner, nudged out so
    /// it reads as attached to the tile rather than floating inside it.
    func userRecipeBadge(_ isUserRecipe: Bool, size: CGFloat = 18) -> some View {
        overlay(alignment: .topTrailing) {
            if isUserRecipe {
                UserRecipeBadge(size: size)
                    .offset(x: size * 0.28, y: -size * 0.28)
            }
        }
    }
}
