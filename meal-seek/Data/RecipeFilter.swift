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

    /// Recipes whose cuisine is one of the user's selected cuisines.
    static func inCuisines(_ recipes: [Recipe], cuisines: Set<String>) -> [Recipe] {
        recipes.filter { cuisines.contains($0.cuisine) }
    }
}
