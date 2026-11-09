//
//  RatingsStore.swift
//  Meal Seek
//
//  Loads and saves recipe like/dislike ratings as a JSON file in the app's
//  Documents directory, same pattern as PreferencesStore. The file is a
//  dictionary keyed by recipe id; a recipe with no entry is unrated.
//

import Foundation

@Observable
final class RatingsStore {
    /// Every rated recipe, keyed by recipe id. No entry means unrated.
    private(set) var ratings: [String: RecipeRating]

    private static let fileName = "ratings.json"

    init() {
        ratings = Self.load()
    }

    func rating(for recipeID: String) -> RecipeRating? {
        ratings[recipeID]
    }

    /// Sets or clears a rating and persists. Passing nil removes the record
    /// entirely — unrated is the absence of an entry, never a stored value.
    func setRating(_ rating: RecipeRating?, for recipeID: String) {
        if let rating {
            ratings[recipeID] = rating
        } else {
            ratings.removeValue(forKey: recipeID)
        }
        save()
    }

    /// Absolute URL of the ratings file in Documents, or nil if it can't be resolved.
    private static func fileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ RatingsStore: could not locate the Documents directory.")
            return nil
        }
        return documents.appendingPathComponent(fileName)
    }

    private static func load() -> [String: RecipeRating] {
        guard let url = fileURL() else { return [:] }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ℹ️ RatingsStore: no ratings file yet — all recipes unrated.")
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let ratings = try JSONDecoder().decode([String: RecipeRating].self, from: data)
            print("✅ RatingsStore: loaded \(ratings.count) rating(s) from \(url.path)")
            return ratings
        } catch {
            print("❌ RatingsStore: failed to read \(url.path) — \(error.localizedDescription). Starting unrated.")
            return [:]
        }
    }

    /// Re-reads ratings from disk into the in-memory dictionary. Used after a
    /// data restore so the library and detail views reflect the restored file
    /// without a relaunch.
    func reload() {
        ratings = Self.load()
    }

    /// Replaces every rating with `newRatings` and persists in one step.
    /// Throws on write failure so a restore can report a partial failure.
    func restore(_ newRatings: [String: RecipeRating]) throws {
        guard let url = Self.fileURL() else { throw BackupError.documentsUnavailable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(newRatings)
        try data.write(to: url, options: .atomic)
        ratings = newRatings
    }

    /// Persist the current ratings to disk. Errors are reported, never fatal.
    private func save() {
        guard let url = Self.fileURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ratings)
            try data.write(to: url, options: .atomic)
            print("✅ RatingsStore: saved \(ratings.count) rating(s) to \(url.path)")
        } catch {
            print("❌ RatingsStore: failed to save ratings — \(error.localizedDescription)")
        }
    }
}
