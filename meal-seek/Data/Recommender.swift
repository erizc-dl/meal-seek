//
//  Recommender.swift
//  Meal Seek
//
//  The recipe "generator" behind the three Home paths. Pure functions over
//  the recipe pool: no storage, no UI. Every path runs the pool through
//  `RecipeFilter.safe` FIRST, so a recipe with one of the user's allergens,
//  or one that doesn't fit their diets, can never be ranked or returned.
//
//  Path 1 "Cook with what I have": fridge ingredients (required) + cuisines
//  (optional) → at most 5 recipes. Ranked by
//    1. how many of the user's ingredients the recipe uses (most first);
//    2. at an equal count, a picked cuisine before any other;
//    3. then the fewest ingredients still to buy, the shortest time, the name.
//  So a recipe that uses your ingredients always beats one that only matches
//  your cuisine, and recipes that use none of them only fill empty places.
//
//  Path 2 "I want to plan a meal": cuisines (required) + meal preferences
//  (optional: low budget / under 30 min / low calorie). Only recipes from the
//  picked cuisines; those meeting the most picked preferences come first.
//
//  Path 3 "I have something in mind": no ranking, the safe library A–Z with
//  the dropdown and search.
//

import Foundation

enum Recommender {
    /// Path 1 shows at most this many recipes.
    static let fridgeLimit = 5

    /// The 11 cuisines, in the designs' picker order.
    static let cuisines = [
        "Chinese", "American", "Japanese", "Korean", "Spanish", "Italian",
        "French", "Indian", "Mexican", "Thai", "German",
    ]

    /// Path 2 meal preferences, as stored in `Recipe.cuisineType`.
    static let mealPreferences = ["low_budget", "under_30_min", "low_calorie"]

    // MARK: Path 1

    struct FridgeMatch: Identifiable {
        let recipe: Recipe
        /// The user's ingredients this recipe uses, in the user's order.
        let usedIngredients: [String]
        /// Recipe ingredients the user has ("✓" chips).
        let have: [String]
        /// Recipe ingredients still to buy ("✗" chips). Assumed pantry items
        /// (salt, water, oil, black pepper) are in neither list.
        let missing: [String]
        let isPreferredCuisine: Bool

        var id: String { recipe.id }
        var matchCount: Int { usedIngredients.count }
        /// Share of the recipe's ingredients the user has, 0–100.
        var percent: Int {
            let total = have.count + missing.count
            return total == 0 ? 0 : Int((Double(have.count) * 100 / Double(total)).rounded())
        }
        /// "Show: Require grocery run" vs "Your ingredients only".
        var needsGroceryRun: Bool { !missing.isEmpty }
    }

    struct FridgeResult {
        let matches: [FridgeMatch]
        /// Recipes hidden by the user's allergies and diets.
        let hiddenCount: Int
    }

    static func fridge(
        ingredients: [String],
        cuisines: Set<String>,
        recipes: [Recipe],
        profile: SafetyProfile,
        limit: Int = fridgeLimit
    ) -> FridgeResult {
        let fridge = cleaned(ingredients)
        guard !fridge.isEmpty else { return FridgeResult(matches: [], hiddenCount: 0) }
        let (pool, hidden) = RecipeFilter.safe(recipes, for: profile)
        let fridgeWords = fridge.map { IngredientMatcher.words(of: $0) }

        let scored = pool.map { recipe -> FridgeMatch in
            var used: [String] = []
            var have: [String] = []
            var missing: [String] = []
            var seen = Set<String>()
            for ingredient in recipe.ingredients
            where !IngredientMatcher.assumedPantry.contains(ingredient.name) && seen.insert(ingredient.name).inserted {
                let neededWords = IngredientMatcher.words(of: ingredient.name)
                let users = fridge.indices
                    .filter { IngredientMatcher.matches(words: fridgeWords[$0], words: neededWords) }
                    .map { fridge[$0] }
                if users.isEmpty {
                    missing.append(ingredient.name)
                } else {
                    have.append(ingredient.name)
                    for user in users where !used.contains(user) { used.append(user) }
                }
            }
            used.sort { fridge.firstIndex(of: $0)! < fridge.firstIndex(of: $1)! }
            return FridgeMatch(
                recipe: recipe, usedIngredients: used, have: have, missing: missing,
                isPreferredCuisine: cuisines.contains(recipe.cuisine)
            )
        }

        let ranked = scored.sorted { a, b in
            if a.matchCount != b.matchCount { return a.matchCount > b.matchCount }
            if a.isPreferredCuisine != b.isPreferredCuisine { return a.isPreferredCuisine }
            if a.missing.count != b.missing.count { return a.missing.count < b.missing.count }
            return quickerThenName(a.recipe, b.recipe)
        }
        return FridgeResult(matches: Array(ranked.prefix(max(0, limit))), hiddenCount: hidden)
    }

    // MARK: Path 2

    struct PlanMatch: Identifiable {
        let recipe: Recipe
        /// The picked meal preferences this recipe meets.
        let metPreferences: [String]
        var id: String { recipe.id }
    }

    struct PlanResult {
        let matches: [PlanMatch]
        /// Recipes in the picked cuisines hidden by allergies and diets.
        let hiddenCount: Int
    }

    static func plan(
        cuisines: Set<String>,
        preferences: Set<String>,
        recipes: [Recipe],
        profile: SafetyProfile
    ) -> PlanResult {
        guard !cuisines.isEmpty else { return PlanResult(matches: [], hiddenCount: 0) }
        let inCuisines = RecipeFilter.inCuisines(recipes, cuisines: cuisines)
        let (pool, hidden) = RecipeFilter.safe(inCuisines, for: profile)

        let matches = pool.map { recipe in
            PlanMatch(recipe: recipe, metPreferences: mealPreferences.filter {
                preferences.contains($0) && recipe.cuisineType.contains($0)
            })
        }
        // Tiers by preferences met (most first). Inside a tier the cuisines
        // take turns, so picking Italian + Thai doesn't show 30 Italian
        // dishes before the first Thai one.
        let tiers = Dictionary(grouping: matches, by: \.metPreferences.count)
        var ordered: [PlanMatch] = []
        for met in tiers.keys.sorted(by: >) {
            let byCuisine = Dictionary(grouping: tiers[met]!, by: \.recipe.cuisine)
                .mapValues { $0.sorted { quickerThenName($0.recipe, $1.recipe) } }
            let cuisineOrder = byCuisine.keys.sorted { order(of: $0) < order(of: $1) }
            var index = 0
            var added = true
            while added {
                added = false
                for cuisine in cuisineOrder where index < byCuisine[cuisine]!.count {
                    ordered.append(byCuisine[cuisine]![index])
                    added = true
                }
                index += 1
            }
        }
        return PlanResult(matches: ordered, hiddenCount: hidden)
    }

    // MARK: Path 3 and the recipe library

    struct LibraryResult {
        let recipes: [Recipe]
        let hiddenCount: Int
    }

    /// The dropdown: All, Favorites, one cuisine, or one diet.
    enum LibraryScope: Hashable {
        case all
        case favorites
        case cuisine(String)
        case diet(String)
    }

    static func library(
        recipes: [Recipe],
        profile: SafetyProfile,
        scope: LibraryScope = .all,
        favoriteIDs: Set<String> = [],
        search: String = ""
    ) -> LibraryResult {
        let scoped = recipes.filter { recipe in
            switch scope {
            case .all: return true
            case .favorites: return favoriteIDs.contains(recipe.id)
            case .cuisine(let cuisine): return recipe.cuisine == cuisine
            case .diet(let diet): return RecipeFilter.isSafe(recipe, for: SafetyProfile(diets: [diet]))
            }
        }
        let (safe, hidden) = RecipeFilter.safe(scoped, for: profile)
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = needle.isEmpty ? safe : safe.filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return LibraryResult(
            recipes: found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            hiddenCount: hidden
        )
    }

    // MARK: Helpers

    /// Trimmed, non-empty, without duplicates, in the user's order.
    static func cleaned(_ ingredients: [String]) -> [String] {
        var seen = Set<String>()
        return ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func quickerThenName(_ a: Recipe, _ b: Recipe) -> Bool {
        let timeA = a.prepTimeMinutes + a.cookTimeMinutes
        let timeB = b.prepTimeMinutes + b.cookTimeMinutes
        if timeA != timeB { return timeA < timeB }
        if a.name != b.name { return a.name < b.name }
        return a.id < b.id
    }

    private static func order(of cuisine: String) -> Int {
        cuisines.firstIndex(of: cuisine) ?? cuisines.count
    }
}
