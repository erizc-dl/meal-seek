//
//  UserRecipeStore.swift
//  Meal Seek
//
//  User-created recipes, stored as their own local JSON file in Documents —
//  the same pattern as RatingsStore. They are a SEPARATE ISLAND from the
//  bundled 647-recipe database:
//
//  - never merged into meal-seek-recipes.json, which stays read-only;
//  - user-only, on this device, in this file;
//  - surfaced alongside built-ins in the library and eligible for planning,
//    because RecipeStore concatenates the two pools.
//
//  Provenance lives OUTSIDE the recipe. A user recipe is a plain `Recipe` —
//  the same type, the same fields, the same JSON shape as a bundled one — and
//  is identified as user-created only by the `userIDPrefix` on its id. That
//  is deliberate: a future "share to social" feature COPIES a recipe out
//  (see `exportPayload`), and because the value being copied is already a
//  standard `Recipe` inside a standard `RecipeDatabase` envelope, sharing
//  needs no new type, no conversion, and no mutation of the local original.
//  Nothing in this file writes back into the bundle.
//

import Foundation

/// The on-disk envelope. Mirrors `RecipeDatabase` so an exported single
/// recipe and the bundled database are the same shape.
struct UserRecipeFile: Codable {
    /// Bumped only if this envelope changes incompatibly.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let recipes: [Recipe]
}

@Observable
final class UserRecipeStore {
    /// Every user-created recipe, newest first (the order they are shown in
    /// the library's "Mine" filter).
    private(set) var recipes: [Recipe] = []

    /// Prefix on every user recipe id. Guarantees a user id can never collide
    /// with a bundled one, and lets provenance survive backup and restore
    /// without a parallel record.
    static let userIDPrefix = "user-"

    private static let fileName = "user-recipes.json"

    init() {
        recipes = Self.load()
    }

    /// Whether the id belongs to a user-created recipe. The one provenance
    /// check in the app — cheap enough to call from a view body.
    static func isUserRecipe(id: String) -> Bool {
        id.hasPrefix(userIDPrefix)
    }

    /// A fresh id for a recipe the user is creating.
    static func makeID() -> String {
        userIDPrefix + UUID().uuidString
    }

    // MARK: Mutation

    /// Adds a new recipe, or replaces an existing one with the same id.
    /// Persists immediately — there is no unsaved state to lose.
    func save(_ recipe: Recipe) {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        persist()
    }

    func delete(id: String) {
        recipes.removeAll { $0.id == id }
        persist()
    }

    func recipe(id: String) -> Recipe? {
        recipes.first { $0.id == id }
    }

    // MARK: Sharing (groundwork only — nothing here sends anything)

    /// A standalone, shareable copy of one recipe in the same envelope shape
    /// as the bundled database. Pure value out; the stored recipe is never
    /// touched, so a future share feature cannot disturb the local original.
    func exportPayload(for recipeID: String) -> UserRecipeFile? {
        guard let recipe = recipe(id: recipeID) else { return nil }
        return UserRecipeFile(formatVersion: UserRecipeFile.currentFormatVersion, recipes: [recipe])
    }

    // MARK: Persistence

    private static func fileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ UserRecipeStore: could not locate the Documents directory.")
            return nil
        }
        return documents.appendingPathComponent(fileName)
    }

    private static func load() -> [Recipe] {
        guard let url = fileURL() else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ℹ️ UserRecipeStore: no user recipe file yet.")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(UserRecipeFile.self, from: data)
            guard file.formatVersion <= UserRecipeFile.currentFormatVersion else {
                print("❌ UserRecipeStore: file format \(file.formatVersion) is newer than this app understands. " +
                      "Leaving it untouched and starting empty so nothing is overwritten.")
                return []
            }
            print("✅ UserRecipeStore: loaded \(file.recipes.count) user recipe(s).")
            return file.recipes
        } catch {
            print("❌ UserRecipeStore: failed to read \(url.path) — \(error.localizedDescription). Starting empty.")
            return []
        }
    }

    private func persist() {
        guard let url = Self.fileURL() else { return }
        do {
            try Self.encode(recipes).write(to: url, options: .atomic)
        } catch {
            print("❌ UserRecipeStore: failed to write \(url.path) — \(error.localizedDescription)")
        }
    }

    private static func encode(_ recipes: [Recipe]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            UserRecipeFile(formatVersion: UserRecipeFile.currentFormatVersion, recipes: recipes)
        )
    }

    // MARK: Backup & restore

    /// Re-reads from disk after a restore so views update without a relaunch.
    func reload() {
        recipes = Self.load()
    }

    /// Replaces every user recipe and persists in one step. Throws so a
    /// restore can report a partial failure, matching the other stores.
    func restore(_ newRecipes: [Recipe]) throws {
        guard let url = Self.fileURL() else { throw BackupError.documentsUnavailable }
        try Self.encode(newRecipes).write(to: url, options: .atomic)
        recipes = newRecipes
    }
}
