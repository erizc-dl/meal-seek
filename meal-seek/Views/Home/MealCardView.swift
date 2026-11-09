//
//  MealCardView.swift
//  Meal Seek
//
//  One meal slot on the Home screen: a white card LISTING every dish in the
//  slot, or a dashed pale placeholder when the slot is empty.
//
//  The card is a container, not a single-recipe row. The meal-type label and
//  the icon tile appear once for the card; each dish gets its own row with its
//  own tap target (push the recipe) and its own menu (replace or remove that
//  dish alone), reachable from a visible trailing ellipsis button OR from a
//  long-press on the row. The ellipsis is the discoverable route; the
//  long-press is kept because users who learned it should not lose it.
//
//  There is deliberately NO whole-card tap target — tapping the card's
//  background outside a dish row does nothing, because on a
//  four-dish card "which recipe did I just open?" has no good answer.
//
//  This supersedes the old summary affordances: the "+n more" line and the
//  "n / 4" capsule both existed to hint at dishes the card could not show, and
//  the card now shows them by name.
//

import SwiftUI

/// The fixed SF Symbol for each meal type. Deliberately per-meal-type, not
/// per-recipe: every breakfast shows the same icon.
enum MealTypeIcon {
    static func symbol(for mealType: String) -> String {
        switch mealType {
        case "breakfast": return "cup.and.saucer.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.stars.fill"
        default: return "fork.knife"
        }
    }
}

struct MealCardView: View {
    let mealType: String
    /// The slot's dishes, already resolved and in `selectedIDs` order. Ids that
    /// no longer resolve are dropped by the caller rather than rendered blank —
    /// so a slot with one stale id still shows its other dishes.
    let dishes: [Recipe]
    /// Drives the "+ Add dish" row. False on a full slot, on breakfast (whose
    /// ceiling is 1), and on past weeks. No meal type is special-cased here;
    /// the answer comes from `PlanGenerator.maxSelectedDishes(for:)`.
    var canAddDish: Bool = false
    /// Past weeks are historical: rows still open the recipe, but nothing on
    /// the card can change the plan.
    var isEditable: Bool = true
    let ratingsStore: RatingsStore
    /// When true, THIS card's first dish menu button is the walkthrough's
    /// "every dish can be swapped" target. Only one card on the screen sets it,
    /// so only one view ever claims the step.
    var carriesDishMenuSpotlight: Bool = false
    var onAddDish: (() -> Void)?
    /// Called with the id of the dish to swap / drop.
    var onReplaceDish: ((String) -> Void)?
    var onRemoveDish: ((String) -> Void)?

    /// Display-layer localization of recipe names; English fallback.
    @Environment(\.recipeTranslations) private var translations

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconTile

            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedNames.mealType(mealType))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.textTertiary)
                    .padding(.bottom, 4)

                ForEach(Array(dishes.enumerated()), id: \.element.id) { index, recipe in
                    if index > 0 {
                        divider
                    }
                    dishRow(recipe, isSpotlightTarget: carriesDishMenuSpotlight && index == 0)
                }

                if canAddDish {
                    divider
                    addDishRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    /// Fixed per meal type, never per recipe — a slot showing four dishes still
    /// shows one icon for the meal, and it belongs to the card rather than to
    /// any dish in it.
    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.brandOrangePale)
            Image(systemName: MealTypeIcon.symbol(for: mealType))
                .font(.system(size: 22))
                .foregroundStyle(.brandOrange)
        }
        .frame(width: 46, height: 46)
    }

    /// Sits inside the dish column, so it is already inset from the card edge by
    /// the icon tile's width — the Account settings group's treatment, achieved
    /// by the layout rather than by a hardcoded leading pad.
    private var divider: some View {
        Rectangle()
            .fill(Color.backgroundSecondary)
            .frame(height: 0.5)
    }

    // MARK: Dish row

    /// Tap pushes THIS recipe; the trailing ellipsis and a long-press both act
    /// on THIS dish. All three are scoped to the row, which is what makes a
    /// multi-dish card editable at all.
    ///
    /// The ellipsis is a SIBLING of the NavigationLink, not a child of its
    /// label: a Button nested inside a link's label does not reliably receive
    /// its own taps, because the link's own gesture wins. So the link shrinks
    /// to wrap the name and capsule, and the menu button sits beside it.
    private func dishRow(_ recipe: Recipe, isSpotlightTarget: Bool = false) -> some View {
        HStack(spacing: 0) {
            NavigationLink {
                RecipeDetailView(recipe: recipe, ratingsStore: ratingsStore)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let roleLabel = roleLabel(for: recipe) {
                        // ABOVE the name, not beside it. The row's scarce axis is
                        // horizontal -- the name is lineLimit(3) precisely because
                        // it competes with the capsule and the 44pt menu button,
                        // and the longest Spanish role word is 10 characters. A
                        // second capsule or a "Main · Chinese · 25m" merge would
                        // take the width back out of the name. Vertical is the
                        // cheap axis here, for the same reason lineLimit(3) is
                        // affordable: Home scrolls.
                        //
                        // Above rather than below because the name runs 1-3 lines.
                        // Below, the labels would land at ragged offsets; above,
                        // they pin to each row's top edge and form a column the eye
                        // can scan, which is the entire point of showing them.
                        //
                        // 11 medium textTertiary is the card's OWN meal-type label
                        // style -- the same kind of fact one level down. It is also
                        // the untracked 11pt style, so it cannot be confused with
                        // the tracked UPPERCASE section headers (§2).
                        Text(roleLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.textTertiary)
                    }

                    HStack(spacing: 8) {
                        Text(translations.name(for: recipe))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.textPrimary)
                            .multilineTextAlignment(.leading)
                            // 3, not 2: at 2 the longest Spanish names truncate on
                            // the primary screen, and Spanish is the corpus's
                            // longest language. Affordable only because Home
                            // scrolls -- see the fixedSize note below.
                            .lineLimit(3)
                            // Without this the name TRUNCATES at one line instead of
                            // using the extra lines that lineLimit(3) already allows: in
                            // an HStack, Text reports its one-line ideal height and
                            // then clips to the narrower width it actually gets. The
                            // trailing menu button made that width tighter, so names
                            // that used to wrap started truncating.
                            //
                            // This REQUIRES Home to scroll. Wrapped names make a
                            // four-dish card taller than the screen, which is why
                            // the loaded week is now inside a ScrollView. Do not
                            // keep this line if that ScrollView ever goes away.
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Text("\(LocalizedNames.cuisine(recipe.cuisine)) · \(recipe.prepTimeMinutes + recipe.cookTimeMinutes)m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.textOnPale)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.brandOrangePale))
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .contextMenu {
                // Past weeks get the tap target but no edits. Unchanged: the
                // long-press remains a complete route to both actions.
                if isEditable {
                    dishMenuItems(recipe)
                }
            }

            // Same gating as the long-press, so a past week's card carries no
            // edit affordance at all rather than a dead button.
            if isEditable {
                dishMenuButton(recipe, isSpotlightTarget: isSpotlightTarget)
            }
        }
    }

    /// The role label for a dish row, or nil when the row shows none.
    ///
    /// Two things suppress it. `DishRole.displayLabel` drops `all_in_one` and
    /// `unassigned`, which is the rule about ROLES. This adds the rule about
    /// SLOTS: a slot that does not compose has no structure to explain, so
    /// labelling its one dish is noise. That is breakfast today, and the test
    /// is `PlanGenerator.multiDishMealTypes` rather than a literal
    /// `!= "breakfast"` — the same single source of truth the "+ Add dish" row
    /// and the dish ceiling already derive from, so no meal type is
    /// special-cased in this view and making breakfast composed later needs no
    /// edit here.
    ///
    /// It is a real gate, not a defensive one: 13 of the 169 breakfast recipes
    /// carry `role == .main` and would otherwise show a label.
    private func roleLabel(for recipe: Recipe) -> String? {
        guard PlanGenerator.multiDishMealTypes.contains(mealType) else { return nil }
        return LocalizedNames.cardRole(recipe.role)
    }

    /// The visible counterpart to the long-press: the same two actions, on a
    /// control a user can actually see. Everything Replace/Remove does stays
    /// reachable both ways.
    private func dishMenuButton(_ recipe: Recipe, isSpotlightTarget: Bool = false) -> some View {
        Menu {
            dishMenuItems(recipe)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                // textSecondary, NOT textTertiary. Tertiary (#ABABAB) is the
                // token for captions, inactive and disabled; this is an active
                // control. It also measures 2.30:1 against the white card,
                // under WCAG 2.2's 3:1 floor for non-text UI components.
                // #6B6B6B is 5.33:1 and costs no width -- the layout is
                // pixel-identical. Do not "harmonize" this back to tertiary.
                .foregroundStyle(.textSecondary)
                // A REAL 44x44 target. The previous version framed 44pt wide
                // and then clawed the layout back with .padding(.horizontal,
                // -12), on the theory that hit testing would still extend past
                // the layout box. Measured on device: it does not. The button's
                // actual target was 20 x 34.3pt, and the "44pt HIG minimum"
                // recorded in DESIGN_SYSTEM was never true.
                //
                // The trick existed because a wider button pushed dish names
                // into truncation on a screen that did not scroll. Home scrolls
                // now and the name is lineLimit(3), so the cost of those 24pt
                // is a line of wrapping, not lost text. The workaround outlived
                // its reason.
                .frame(width: Self.menuHitWidth, height: Self.menuHitWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Dish options")
        // The cutout traces the 44pt hit area, not the 13pt glyph -- pointing at
        // the glyph alone would spotlight something smaller than the thing the
        // user has to hit.
        .spotlightTarget(isSpotlightTarget ? .swapDish : nil, cornerRadius: 10)
    }

    /// The two dish actions, shared verbatim by the long-press context menu and
    /// the ellipsis menu so the two routes can never drift apart.
    @ViewBuilder
    private func dishMenuItems(_ recipe: Recipe) -> some View {
        Button {
            onReplaceDish?(recipe.id)
        } label: {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
        }
        Button(role: .destructive) {
            onRemoveDish?(recipe.id)
        } label: {
            Label("Remove", systemImage: "minus.circle")
        }
    }

    /// The dish menu button's hit target, square, at the HIG minimum.
    private static let menuHitWidth: CGFloat = 44

    // MARK: Add dish

    private var addDishRow: some View {
        Button {
            onAddDish?()
        } label: {
            HStack(spacing: 0) {
                Text("+ Add dish")
                    .font(.system(size: 14))
                    .foregroundStyle(.textOnPale)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Rendered when a meal type has no planned recipe (empty generator pool, a
/// stale recipe ID, or a removed meal). Never a blank card, never a crash.
/// With `onAdd` set (current/future weeks) it's a tappable "+ Add meal"
/// button; without it (past weeks) it's an inert placeholder.
struct EmptyMealSlotView: View {
    let mealType: String
    var onAdd: (() -> Void)?

    var body: some View {
        if let onAdd {
            Button(action: onAdd) {
                card(label: "+ Add meal", labelOpacity: 1)
            }
            .buttonStyle(PressableButtonStyle())
        } else {
            card(label: "No meal planned", labelOpacity: 0.7)
        }
    }

    private func card(label: LocalizedStringKey, labelOpacity: Double) -> some View {
        VStack(spacing: 4) {
            // Full-strength textOnPale: text on the pale orange surface is
            // always #993C1D, never the muted caption color of white cards.
            Text(LocalizedNames.mealType(mealType))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.textOnPale)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.textOnPale.opacity(labelOpacity))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.brandOrangePale)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.textOnPale.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }
}
