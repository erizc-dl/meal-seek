//
//  RecipeStore.swift
//  Meal Seek
//
//  Loads and decodes the bundled recipe database once on launch.
//

import Foundation

@Observable
final class RecipeStore {
    /// The bundled database plus the user's own recipes, in that order — the
    /// one pool every consumer reads (library, filters, generation, grocery).
    /// User recipes are stored separately (see `UserRecipeStore`) and merged
    /// only here; the bundled JSON is never written to.
    private(set) var recipes: [Recipe] = []
    /// Just the bundled 647. Kept separate so a restore can tell a bundled
    /// recipe id from a user one, and so `catalog` stays stable.
    private(set) var bundledRecipes: [Recipe] = []
    /// The user's own recipes. Mutate through this store's `saveUserRecipe` /
    /// `deleteUserRecipe` so the merged pool is rebuilt in the same step.
    let userRecipes: UserRecipeStore
    /// Schema version of the bundled recipe database (`schemaVersion` at the
    /// root of meal-seek-recipes.json). Recorded in data backups so a restore
    /// can detect a file made against a different recipe set. 0 if load failed.
    private(set) var schemaVersion: Int = 0
    /// The reason loading/decoding failed, or nil on success. Passed to the
    /// week generator so a `databaseLoadFailed` diagnostic can name the cause
    /// (the same text already printed to the console).
    private(set) var loadFailureReason: String?
    /// The region → cuisine grouping derived from the BUNDLED recipes only,
    /// computed once. User recipes pick their cuisine from this catalog rather
    /// than inventing one, so adding them can never introduce a region or
    /// cuisine the catalog doesn't already have; only the per-cuisine counts
    /// shown in the picker exclude them.
    private(set) var catalog: CuisineCatalog
    /// Canonical ingredient names for Add Recipe's suggestion dropdown, built
    /// once from the bundled recipes. Bundled-only on purpose: a user's own
    /// free-typed ingredients are not canon and must not be suggested back.
    private(set) var ingredientCatalog: IngredientCatalog

    init(userRecipes: UserRecipeStore = UserRecipeStore()) {
        let loaded = Self.loadDatabase()
        self.userRecipes = userRecipes
        bundledRecipes = loaded.recipes
        recipes = loaded.recipes + userRecipes.recipes
        schemaVersion = loaded.schemaVersion
        loadFailureReason = loaded.failureReason
        catalog = CuisineCatalog(recipes: loaded.recipes)
        ingredientCatalog = IngredientCatalog(recipes: loaded.recipes)
    }

    // MARK: User recipes

    /// Adds or updates a user recipe and rebuilds the merged pool. The only
    /// supported way to mutate user recipes — writing to `userRecipes`
    /// directly would leave `recipes` stale.
    func saveUserRecipe(_ recipe: Recipe) {
        userRecipes.save(recipe)
        rebuildPool()
    }

    /// Deletes a user recipe AND strips it from every saved plan.
    ///
    /// `planStore` is a required parameter rather than a property or an
    /// optional, so the compiler stops a future caller deleting a recipe
    /// without pruning the plans that point at it. This codebase has already
    /// made the same omission at four separate sites (see
    /// tests/slot-invariant), and the pattern there is the lesson: make the
    /// rule impossible to skip rather than remembering it.
    ///
    /// The grocery list needs nothing here — it resolves ids against the pool
    /// on every render, so a deleted recipe already contributes nothing to it.
    /// What the plan file loses is a dangling id that still counted against the
    /// 8-dish ceiling and blanked its slot when it was the headline dish.
    ///
    /// Returns the number of planned dishes removed, for the caller's message.
    @discardableResult
    func deleteUserRecipe(id: String, planStore: WeekPlanStore) -> Int {
        userRecipes.delete(id: id)
        rebuildPool()
        return planStore.removeRecipe(id: id)
    }

    /// Re-reads user recipes from disk (after a restore) and rebuilds the pool.
    func reloadUserRecipes() {
        userRecipes.reload()
        rebuildPool()
    }

    private func rebuildPool() {
        recipes = bundledRecipes + userRecipes.recipes
    }

    private static func loadDatabase() -> (recipes: [Recipe], schemaVersion: Int, failureReason: String?) {
        guard let url = Bundle.main.url(forResource: "meal-seek-recipes", withExtension: "json") else {
            let reason = "Could not find meal-seek-recipes.json in the app bundle."
            print("❌ RecipeStore: \(reason) " +
                  "Make sure it is included in the target's Copy Bundle Resources build phase.")
            return ([], 0, reason)
        }

        do {
            let data = try Data(contentsOf: url)
            let database = try JSONDecoder().decode(RecipeDatabase.self, from: data)
            print("✅ RecipeStore: loaded \(database.recipes.count) recipes (schemaVersion \(database.schemaVersion)).")
            return (database.recipes, database.schemaVersion, nil)
        } catch let DecodingError.keyNotFound(key, context) {
            let reason = "Missing key '\(key.stringValue)' at \(Self.path(context.codingPath))."
            print("❌ RecipeStore decoding error: \(reason) — \(context.debugDescription)")
            return ([], 0, reason)
        } catch let DecodingError.typeMismatch(type, context) {
            let reason = "Type mismatch for \(type) at \(Self.path(context.codingPath))."
            print("❌ RecipeStore decoding error: \(reason) — \(context.debugDescription)")
            return ([], 0, reason)
        } catch let DecodingError.valueNotFound(type, context) {
            let reason = "Missing value for \(type) at \(Self.path(context.codingPath))."
            print("❌ RecipeStore decoding error: \(reason) — \(context.debugDescription)")
            return ([], 0, reason)
        } catch let DecodingError.dataCorrupted(context) {
            let reason = "Data corrupted at \(Self.path(context.codingPath))."
            print("❌ RecipeStore decoding error: \(reason) — \(context.debugDescription)")
            return ([], 0, reason)
        } catch {
            let reason = error.localizedDescription
            print("❌ RecipeStore: failed to load recipes — \(reason)")
            return ([], 0, reason)
        }
    }

    /// Renders a decoding coding path as a readable dotted string for the console.
    private static func path(_ codingPath: [CodingKey]) -> String {
        codingPath.map(\.stringValue).joined(separator: ".")
    }
}
