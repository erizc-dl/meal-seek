//
//  RecipeDetailView.swift
//  Meal Seek
//
//  The cooking view for a single recipe: RecipeSymbol hero, name, tag
//  capsules, like/dislike controls, then ingredients and steps in white cards.
//

import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    /// Ratings persist immediately but only influence the NEXT generation —
    /// tapping a thumb never touches the currently displayed week.
    let ratingsStore: RatingsStore
    @Environment(\.walkthrough) private var walkthrough
    /// Only supplied where editing is reachable (the library). Without it the
    /// screen is read-only, which is all a built-in recipe ever needs.
    var recipeStore: RecipeStore?
    /// Supplied alongside `recipeStore` and for the same reason: the edit
    /// screen it opens can delete, and a deletion has to prune saved plans.
    /// Both are nil on the read-only route from a meal card.
    var planStore: WeekPlanStore?
    /// Display-layer localization of name, ingredient lines, and steps. Falls
    /// back to English per field; never affects matching or filtering.
    @Environment(\.recipeTranslations) private var translations
    /// How many people the user is cooking for. Ingredient amounts and the
    /// "Serves" tag both follow it, so the screen never asks the cook to divide
    /// an authored 4-serving recipe in their head. nil (previews, onboarding)
    /// shows the recipe exactly as authored.
    @Environment(\.cookingServings) private var cookingServings

    /// User recipes have no translation record, so their typed text shows
    /// as-is in every language — correct, since the user wrote it.
    private var isUserRecipe: Bool { UserRecipeStore.isUserRecipe(id: recipe.id) }

    /// The servings every amount on this screen is written for.
    private var servings: Int { cookingServings ?? recipe.baseServings }

    /// Ingredients rescaled to `servings`. Display only — the canonical recipe
    /// is untouched, exactly as with the translation layer above.
    private var scaledIngredients: [Ingredient] {
        RecipeScaling.ingredients(of: recipe, forServings: cookingServings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RecipeSymbol(recipe: recipe, size: 160)
                    .userRecipeBadge(isUserRecipe, size: 26)
                    .padding(.top, 8)

                Text(translations.name(for: recipe))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)

                tagRow

                ratingRow

                sectionCard("INGREDIENTS") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(scaledIngredients.enumerated()), id: \.offset) { _, ingredient in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle()
                                    .fill(Color.brandOrange)
                                    .frame(width: 5, height: 5)
                                Text(translations.ingredientLine(ingredient, in: recipe.id))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.textPrimary)
                            }
                        }
                    }
                }

                if !recipe.instructions.isEmpty {
                    sectionCard("STEPS") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text((index + 1).formatted())
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.textOnPale)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.brandOrangePale))
                                    Text(translations.instruction(at: index, in: recipe.id, english: step))
                                        .font(.system(size: 14))
                                        .foregroundStyle(.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .spotlightScreen()
        // The gate is "the detail screen appeared", not "a row was tapped" --
        // a tap that does not result in a push must not advance the step.
        //
        // NOT location-scoped: this fires for a recipe opened from Home too.
        // Benign only because step 8 can only be active after step 7, which is
        // in Account. That is an ordering coincidence, not a guarantee.
        .onAppear { walkthrough.report(.openedRecipeDetail) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only the user's own recipes are editable. Built-ins are the
            // shipped database and stay read-only.
            if isUserRecipe, let recipeStore, let planStore {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AddRecipeView(recipeStore: recipeStore, planStore: planStore, editing: recipe)
                    } label: {
                        Text("Edit")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.brandOrange)
                    }
                }
            }
        }
    }

    // MARK: Tags

    private var tagRow: some View {
        HStack(spacing: 8) {
            tag(LocalizedNames.cuisine(recipe.cuisine))
            tag(String(localized: "\(recipe.prepTimeMinutes + recipe.cookTimeMinutes) min"))
            tag(String(localized: "Serves \(servings)"))
        }
    }

    /// Renders a pre-localized string verbatim (cuisine is a localized display
    /// label; the time/serves tags are already resolved via String(localized:)).
    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.textOnPale)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.brandOrangePale))
    }

    // MARK: Rating

    private var ratingRow: some View {
        HStack(spacing: 20) {
            ratingButton(for: .liked, symbol: "hand.thumbsup")
            ratingButton(for: .disliked, symbol: "hand.thumbsdown")
        }
        .spotlightTarget(.ratings, cornerRadius: 12)
    }

    /// Filled orange when active, outlined gray otherwise. Tapping the active
    /// thumb clears back to unrated — ratings are always reversible.
    private func ratingButton(for rating: RecipeRating, symbol: String) -> some View {
        let isActive = ratingsStore.rating(for: recipe.id) == rating
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                ratingsStore.setRating(isActive ? nil : rating, for: recipe.id)
            }
        } label: {
            Image(systemName: isActive ? "\(symbol).fill" : symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isActive ? Color.brandOrange : .textTertiary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: Section card

    private func sectionCard<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.textOnPale)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}
