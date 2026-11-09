//
//  Recipe.swift
//  Meal Seek
//
//  Codable models mirroring meal-seek-recipes.json (schemaVersion 1).
//

import Foundation

/// Top-level container matching the root of meal-seek-recipes.json.
struct RecipeDatabase: Codable {
    let schemaVersion: Int
    let recipes: [Recipe]
}

struct Recipe: Codable, Identifiable {
    let id: String
    let name: String
    let cuisine: String
    /// One or more of "Americas", "European", "Asian". Added in the updated JSON schema.
    let regions: [String]
    let mealTypes: [String]
    let tags: [String]
    let allergens: [String]
    let baseServings: Int
    let prepTimeMinutes: Int
    let cookTimeMinutes: Int
    let ingredients: [Ingredient]
    let instructions: [String]
    let nutrition: Nutrition

    /// What part of a meal this dish plays. Added after schemaVersion 1
    /// shipped, so it is optional on the wire and defaults to `.unassigned`
    /// — see the decoding extension below. Inert today: no generation, UI, or
    /// grocery code reads it.
    var role: DishRole = .unassigned

    /// Whether this dish is a soup. Only meaningful when `role` is `.side`,
    /// where it will later keep two soups out of one meal and push the soup to
    /// the end of the display order. False for every other role.
    var isSoup: Bool = false

    /// Whether this dish crosses cuisines. Only meaningful when `role` is
    /// `.staple` or `.side`.
    ///
    /// `cuisine` is a single mandatory string and a slot draws one cuisine, so
    /// a dish is normally reachable only from its own cuisine. Steamed rice is
    /// wanted by nine cuisines and can only be filed under one of them. This
    /// flag is how the other eight reach it: generation will prefer a
    /// same-cuisine dish and fall back to the universal pool when the cuisine
    /// has none. Nothing reads it yet.
    ///
    /// Chosen over the alternatives deliberately. A secondary cuisine LIST
    /// means editing all 656 recipes for a problem one boolean solves. An
    /// eighteenth "Universal" cuisine value would surface as a browsable
    /// cuisine, because `CuisineCatalog` is derived from the corpus at runtime.
    /// Duplicating a recipe per cuisine was ruled out earlier as the
    /// ~200-recipe path in disguise.
    ///
    /// Known limit, recorded rather than designed around: universality here is
    /// GLOBAL, while some staples are only regionally universal — crusty bread
    /// belongs beside a Spanish, Italian or French main but not a Japanese one.
    /// It is therefore NOT universal, and only Spanish reaches it. `regions`
    /// already exists and could scope this later; a bool cannot. Logged as a
    /// Phase 2 refinement in PRE_LAUNCH.md — do not widen the bool instead.
    var isUniversal: Bool = false
}

// Decoding lives in an extension so the memberwise initializer keeps being
// synthesized for the three call sites that build a `Recipe` in code
// (`RecipeDraft.makeRecipe`, `RecipeSymbol`'s preview, the test harnesses).
extension Recipe {
    /// Hand-written because Swift's synthesized `init(from:)` does NOT fall
    /// back to a property's default value when its key is absent — it throws.
    /// `role`, `isSoup` and `isUniversal` all post-date the recipes already
    /// sitting in a beta tester's `Documents/user-recipes.json` and inside
    /// saved backup archives, so each must decode as absent. Every other field stays
    /// required: a missing `name` is still a corrupt record, and
    /// `RecipeStore` reports it as one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cuisine = try container.decode(String.self, forKey: .cuisine)
        regions = try container.decode([String].self, forKey: .regions)
        mealTypes = try container.decode([String].self, forKey: .mealTypes)
        tags = try container.decode([String].self, forKey: .tags)
        allergens = try container.decode([String].self, forKey: .allergens)
        baseServings = try container.decode(Int.self, forKey: .baseServings)
        prepTimeMinutes = try container.decode(Int.self, forKey: .prepTimeMinutes)
        cookTimeMinutes = try container.decode(Int.self, forKey: .cookTimeMinutes)
        ingredients = try container.decode([Ingredient].self, forKey: .ingredients)
        instructions = try container.decode([String].self, forKey: .instructions)
        nutrition = try container.decode(Nutrition.self, forKey: .nutrition)
        role = try container.decodeIfPresent(DishRole.self, forKey: .role) ?? .unassigned
        isSoup = try container.decodeIfPresent(Bool.self, forKey: .isSoup) ?? false
        isUniversal = try container.decodeIfPresent(Bool.self, forKey: .isUniversal) ?? false
    }
}

struct Ingredient: Codable {
    let name: String
    /// Nullable in JSON: absent for "to taste" items. May be a decimal (e.g. 0.5).
    let quantity: Double?
    /// Nullable in JSON: absent for "to taste" items.
    let unit: String?
    /// Nullable in JSON: e.g. "minced", "to taste", or absent.
    let preparation: String?
    let category: String
}

/// All values are currently null in the data but the fields exist in the schema.
struct Nutrition: Codable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

extension Ingredient {
    /// A readable single line combining quantity, unit, name and preparation,
    /// gracefully omitting any null fields so nothing renders as "nil" or "0".
    /// Examples: "600 g ground beef", "0.5 tsp salt", "salt, to taste".
    var displayText: String { displayText() }

    /// The same composition as `displayText`, but any of name, unit, or
    /// preparation may be overridden with a localized rendering. Quantity
    /// formatting is unchanged, and a nil override falls back to the canonical
    /// English piece — so the display layer swaps only what it has a translation
    /// for. Used by `RecipeTranslationStore.ingredientLine`.
    func displayText(
        nameOverride: String? = nil,
        unitOverride: String? = nil,
        preparationOverride: String? = nil
    ) -> String {
        // Build the leading "quantity unit name" portion, skipping missing pieces.
        var components: [String] = []
        if let quantity {
            components.append(Self.formatQuantity(quantity))
        }
        let unit = unitOverride ?? self.unit
        if let unit, !unit.isEmpty {
            components.append(unit)
        }
        components.append(nameOverride ?? name)

        var line = components.joined(separator: " ")
        let preparation = preparationOverride ?? self.preparation
        if let preparation, !preparation.isEmpty {
            line += ", \(preparation)"
        }
        return line
    }

    /// Formats a quantity dropping any trailing ".0" (600.0 -> "600", 0.5 -> "0.5").
    private static func formatQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }
}
