//
//  MealPickerFilter.swift
//  Meal Seek
//
//  The meal picker's pure recipe filter, extracted from MealPickerView so it is
//  Foundation-only and exercised by the translation harness. Behavior is
//  identical to the former MealPickerView.filteredRecipes, with one addition:
//  the free-text search now matches the active-language name as well as the
//  canonical English name (see `filtered`).
//
//  DISPLAY-ONLY CONTRACT: the translation store is consulted for the search
//  match and the final display ordering ONLY. Allergen exclusion, cuisine scope,
//  meal-type narrowing, and the returned Recipe records all read canonical
//  English — a translated string never reaches those eligibility filters or
//  identity. The sort orders by the active-language name so the list reads
//  alphabetically to the user, but that is presentation, not identity.
//

import Foundation

enum MealPickerFilter {
    /// The picker's one filter. Allergen safety comes first and is
    /// unconditional — no parameter can bypass it, mirroring the generator.
    ///
    /// - Parameter translations: consulted solely so the free-text search can
    ///   match the recipe's active-language name and order the results by it;
    ///   never affects which recipes are eligible.
    /// - Parameter narrowingToCuisine: an optional SINGLE cuisine the caller is
    ///   narrowing to, for the dish picker's cuisine chip. It can only ever
    ///   remove recipes from the pool: it is applied last, as a filter over
    ///   whatever survived, and `nil` applies nothing. There is deliberately no
    ///   arrangement of it that widens the pool — in particular it cannot
    ///   reintroduce a recipe the allergen filter above already excluded.
    static func filtered(
        _ recipes: [Recipe],
        slotMealType: String,
        allergens: Set<String>,
        cuisines: Set<String>,
        searchText: String,
        allCuisines: Bool,
        allMealTypes: Bool,
        translations: RecipeTranslationStore,
        narrowingToCuisine: String? = nil
    ) -> [Recipe] {
        var pool = RecipeFilter.allergenSafe(recipes, allergens: allergens)
        if !allCuisines {
            pool = RecipeFilter.inCuisines(pool, cuisines: cuisines)
        }
        if let narrowingToCuisine {
            pool = pool.filter { $0.cuisine == narrowingToCuisine }
        }
        if !allMealTypes {
            pool = pool.filter { $0.mealTypes.contains(slotMealType) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            // Match BOTH the canonical English name and the active-language name,
            // so a query typed in the user's language finds recipes. Record
            // identity stays English; only the display string is also searched.
            pool = pool.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || translations.name(for: $0).localizedCaseInsensitiveContains(query)
            }
        }
        // Order by the active-language display name so the list is alphabetical
        // to the person reading it, matching RecipeLibraryView. Identity and
        // eligibility above stayed canonical English.
        return translations.sortedByDisplayName(pool)
    }
}
