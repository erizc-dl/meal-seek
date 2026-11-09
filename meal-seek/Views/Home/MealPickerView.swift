//
//  MealPickerView.swift
//  Meal Seek
//
//  Sheet for filling a meal slot: local search over the bundled recipes with
//  two widening toggles (all cuisines, all meal types). Allergen exclusion is
//  absolute — there is no toggle for it and there must never be one.
//

import SwiftUI

struct MealPickerView: View {
    /// The meal type of the slot being filled.
    let mealType: String
    let recipes: [Recipe]
    let preferences: UserPreferences
    /// Called with the chosen recipe as the sheet dismisses.
    let onSelect: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Display-layer localization of recipe names; also lets search match the
    /// active-language name. Sheets inherit the app root's injected store.
    @Environment(\.recipeTranslations) private var translations

    // Sheet-local by design: every presentation starts narrow (both off).
    @State private var searchText = ""
    @State private var allCuisines = false
    @State private var allMealTypes = false

    private var results: [Recipe] {
        MealPickerFilter.filtered(
            recipes,
            slotMealType: mealType,
            allergens: preferences.allergens,
            cuisines: preferences.cuisines,
            searchText: searchText,
            allCuisines: allCuisines,
            allMealTypes: allMealTypes,
            translations: translations
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
            toggleRow

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results) { recipe in
                            row(recipe)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .animation(.easeInOut(duration: 0.25), value: results.map(\.id))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.textTertiary)
            TextField("Search recipes", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundCard))
    }

    private var toggleRow: some View {
        HStack(spacing: 10) {
            SelectableChip(label: String(localized: "All cuisines"), isSelected: allCuisines) {
                withAnimation(.easeInOut(duration: 0.25)) { allCuisines.toggle() }
            }
            SelectableChip(label: String(localized: "All meal types"), isSelected: allMealTypes) {
                withAnimation(.easeInOut(duration: 0.25)) { allMealTypes.toggle() }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ recipe: Recipe) -> some View {
        Button {
            dismiss()
            onSelect(recipe)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.brandOrangePale)
                    Image(systemName: MealTypeIcon.symbol(for: mealType))
                        .font(.system(size: 22))
                        .foregroundStyle(.brandOrange)
                }
                .frame(width: 46, height: 46)

                Text(translations.name(for: recipe))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(LocalizedNames.cuisine(recipe.cuisine)) · \(recipe.prepTimeMinutes + recipe.cookTimeMinutes)m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.textOnPale)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.brandOrangePale))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundCard)
                    .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var emptyState: some View {
        Text("No recipes match")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }
}
