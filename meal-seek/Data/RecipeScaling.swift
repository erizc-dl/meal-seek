//
//  RecipeScaling.swift
//  Meal Seek
//
//  Rescales a recipe's ingredient quantities from the servings it was authored
//  for to the servings the user is actually cooking for, so the detail screen
//  shows amounts that can be followed directly instead of leaving the cook to
//  divide every line by four in their head.
//
//  DISPLAY LAYER ONLY, exactly like RecipeTranslationStore: the canonical
//  `Recipe` is never mutated, and nothing downstream — grocery consolidation,
//  allergen derivation, generation, search, ratings — ever sees a scaled
//  quantity. The grocery list scales from the same `householdSize` inside
//  `GroceryListBuilder.aggregate`; this is the same arithmetic for a different
//  surface, not a competing source of truth for it.
//
//  WHY IT DOESN'T JUST CALL GroceryListBuilder.rounded FOR EVERYTHING: that
//  function rounds countable units UP to a whole unit, which is right when you
//  are buying (no shop sells an eighth of an onion) and wrong when you are
//  cooking (a quarter onion goes in the pan happily). Rounding a scaled 0.125
//  onion up to 1 would put four times the onion in the dish — the same class of
//  error this file exists to fix. Measures reuse that tiering unchanged, so
//  there is still only one rule for grams and millilitres.
//

import Foundation

enum RecipeScaling {
    /// `recipe`'s ingredients as they should read for `servings` people.
    ///
    /// Returns the ingredients exactly as authored when there is nothing to do:
    /// no servings in scope (previews, onboarding), a recipe already written for
    /// that many, or a nonsensical `baseServings` that would make the factor
    /// meaningless.
    static func ingredients(of recipe: Recipe, forServings servings: Int?) -> [Ingredient] {
        guard let servings, servings > 0, recipe.baseServings > 0,
              servings != recipe.baseServings else { return recipe.ingredients }
        let factor = Double(servings) / Double(recipe.baseServings)
        return recipe.ingredients.map { scaled($0, by: factor) }
    }

    /// One ingredient at `factor` times its authored quantity, rounded to
    /// something a cook can measure. A to-taste ingredient (no quantity) passes
    /// through untouched.
    static func scaled(_ ingredient: Ingredient, by factor: Double) -> Ingredient {
        // A pinch is a gesture, not a measurement. All seven pinches in the
        // corpus are exactly one, and "0.3 pinch" is false precision — the cook
        // is better served by the word than by arithmetic on it.
        guard let quantity = ingredient.quantity, ingredient.unit != "pinch" else {
            return ingredient
        }
        let (value, unit) = steppedDown(quantity * factor, unit: ingredient.unit)
        return Ingredient(
            name: ingredient.name,
            quantity: rounded(value, unit: unit),
            unit: unit,
            preparation: ingredient.preparation,
            category: ingredient.category
        )
    }

    /// The larger symbol units expressed in their smaller sibling once a scaled
    /// amount falls below one whole unit: "0.35 l" is a worse instruction than
    /// "350 ml", and "0.25 kg" worse than "250 g". This is the mirror of the
    /// display upgrade `GroceryListBuilder.displayValue` already applies in the
    /// other direction, and it uses the same multipliers, so the two agree on
    /// what a litre is. Every other unit passes straight through.
    private static func steppedDown(_ value: Double, unit: String?) -> (Double, String?) {
        guard let unit, value < 1, value > 0 else { return (value, unit) }
        switch unit {
        case "l":  return (value * GroceryListBuilder.volumeUnits["l"]!, "ml")
        case "kg": return (value * GroceryListBuilder.massUnits["kg"]!, "g")
        default:   return (value, unit)
        }
    }

    /// Rounds a scaled quantity to a measurable amount.
    ///
    /// Countable units go to the nearest quarter and never below one quarter, so
    /// a real ingredient can be shrunk but never rounded away to nothing. Weight,
    /// volume and spoons defer to `GroceryListBuilder.rounded`, keeping a single
    /// tiering rule (nearest 5 at ≥ 50, whole at ≥ 10, one decimal below).
    static func rounded(_ value: Double, unit: String?) -> Double {
        if let unit, GroceryListBuilder.countableUnits.contains(unit) {
            guard value > 0 else { return value }
            return max(1, (value * 4).rounded()) / 4
        }
        return GroceryListBuilder.rounded(value, unit: unit)
    }
}
