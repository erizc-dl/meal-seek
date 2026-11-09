//
//  RecipeFilter.swift
//  Meal Seek
//
//  The one shared eligibility filter, used by BOTH the week generator and the
//  meal picker so the rules can never drift apart. Allergen exclusion is
//  absolute — no caller may offer a way around it. Cuisine matching is the
//  default scope, which the picker can explicitly widen.
//

import Foundation

enum RecipeFilter {
    /// Recipes containing none of the user's allergens. Every surface that
    /// offers a recipe (generation, the meal picker) must pass through this.
    static func allergenSafe(_ recipes: [Recipe], allergens: Set<String>) -> [Recipe] {
        recipes.filter { allergens.isDisjoint(with: $0.allergens) }
    }

    /// Whether `recipe` is safe for `profile`: it contains none of the user's
    /// allergens AND fits every diet they picked. This is the ONE rule every
    /// Meal Seek list (Paths 1–3, the recipe library) goes through.
    ///
    /// A diet fits only when the recipe lists it, so a recipe with no diet data
    /// fits no diet (hidden, never shown by mistake). Vegan food is also
    /// vegetarian.
    static func isSafe(_ recipe: Recipe, for profile: SafetyProfile) -> Bool {
        guard profile.allergens.isDisjoint(with: recipe.allergens) else { return false }
        let fits = Set(recipe.dietRestrictions)
        return profile.diets.allSatisfy { diet in
            fits.contains(diet) || (diet == "vegetarian" && fits.contains("vegan"))
        }
    }

    /// The safe recipes, plus how many were hidden (for the "N hidden" banner).
    static func safe(_ recipes: [Recipe], for profile: SafetyProfile) -> (recipes: [Recipe], hiddenCount: Int) {
        let kept = recipes.filter { isSafe($0, for: profile) }
        return (kept, recipes.count - kept.count)
    }

    /// Recipes whose cuisine is one of the user's selected cuisines.
    static func inCuisines(_ recipes: [Recipe], cuisines: Set<String>) -> [Recipe] {
        recipes.filter { cuisines.contains($0.cuisine) }
    }
}

/// What a user can't or won't eat. Allergens use the database's keys
/// ("gluten", "dairy", "egg", "soy", "peanut", "tree_nut", "shellfish",
/// "fish", "sesame"); diets are "kosher", "halal", "vegetarian", "vegan".
struct SafetyProfile: Equatable {
    var allergens: Set<String> = []
    var diets: Set<String> = []

    static let allAllergens = ["gluten", "dairy", "egg", "soy", "peanut", "tree_nut", "shellfish", "fish", "sesame"]
    static let allDiets = ["kosher", "halal", "vegetarian", "vegan"]
}
