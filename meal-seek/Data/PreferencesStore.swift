//
//  PreferencesStore.swift
//  Meal Seek
//
//  Loads and saves UserPreferences as a JSON file in the app's Documents
//  directory. No UserDefaults, SwiftData, or Core Data.
//

import Foundation

@Observable
final class PreferencesStore {
    /// The current preferences. Edited in place during onboarding, then persisted via save().
    var preferences: UserPreferences

    private static let fileName = "preferences.json"

    init() {
        preferences = Self.load()
    }

    /// Absolute URL of the preferences file in Documents, or nil if it can't be resolved.
    private static func fileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ PreferencesStore: could not locate the Documents directory.")
            return nil
        }
        return documents.appendingPathComponent(fileName)
    }

    private static func load() -> UserPreferences {
        guard let url = fileURL() else { return UserPreferences() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ℹ️ PreferencesStore: no preferences file yet — starting onboarding with defaults.")
            return UserPreferences()
        }

        do {
            let data = try Data(contentsOf: url)
            let prefs = try JSONDecoder().decode(UserPreferences.self, from: data)
            print("✅ PreferencesStore: loaded preferences from \(url.path)")
            return prefs
        } catch {
            print("❌ PreferencesStore: failed to read \(url.path) — \(error.localizedDescription). Using defaults.")
            return UserPreferences()
        }
    }

    /// One-time upgrade of a region-level preferences file (pre-17-cuisine
    /// builds) to per-cuisine selection: every stored region expands to all
    /// cuisines now grouped under it, including newly added ones. No-op once
    /// `cuisines` is non-empty. If the catalog is empty (recipe load failure)
    /// nothing is written, so the migration retries on the next launch.
    func migrateRegionsToCuisines(using catalog: CuisineCatalog) {
        guard preferences.cuisines.isEmpty, !preferences.regions.isEmpty else { return }
        let expanded = catalog.cuisineNames(inRegions: preferences.regions)
        guard !expanded.isEmpty else {
            print("❌ PreferencesStore: cannot migrate regions \(preferences.regions.sorted()) — catalog is empty. Will retry next launch.")
            return
        }
        preferences.cuisines = expanded
        save()
        print("ℹ️ PreferencesStore: migrated regions \(preferences.regions.sorted()) to \(expanded.count) cuisines.")
    }

    /// Re-reads preferences from disk into the in-memory copy. Used after a
    /// data restore so the UI reflects the restored file without a relaunch.
    func reload() {
        preferences = Self.load()
    }

    /// Overwrites the preferences file with `newPreferences` and updates the
    /// in-memory copy in one step. Throws on write failure so a restore can
    /// report a partial failure. Deliberately does NOT run
    /// migrateRegionsToCuisines — restored `cuisines`/`regions` are written
    /// verbatim; the launch-time migration only fills an empty `cuisines` set.
    func restore(_ newPreferences: UserPreferences) throws {
        guard let url = Self.fileURL() else { throw BackupError.documentsUnavailable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(newPreferences)
        try data.write(to: url, options: .atomic)
        preferences = newPreferences
    }

    // MARK: Walkthrough progress

    /// Records how far "Plan your first week" got, so an interrupted run
    /// resumes. Written on every step change, which is a handful of tiny writes
    /// across one ~two-minute run.
    /// Takes the raw step identifier rather than the enum: the walkthrough is a
    /// view-layer type and this store is compiled by the logic harnesses.
    func setWalkthroughLastStep(_ rawStep: String) {
        guard preferences.walkthroughLastStep != rawStep else { return }
        preferences.walkthroughLastStep = rawStep
        save()
    }

    /// Marks the walkthrough done, by finishing OR by skipping -- both mean
    /// "do not offer this again unprompted". Clears the resume point so a
    /// replay from Account starts clean.
    func markWalkthroughComplete() {
        guard !preferences.hasCompletedWalkthrough || preferences.walkthroughLastStep != nil else { return }
        preferences.hasCompletedWalkthrough = true
        preferences.walkthroughLastStep = nil
        save()
    }

    /// The user dismissed the Home invitation card. It does not come back.
    func dismissWalkthroughInvitation() {
        guard !preferences.hasDismissedWalkthroughInvitation else { return }
        preferences.hasDismissedWalkthroughInvitation = true
        save()
    }

    /// Persist the current preferences to disk. Errors are reported, never fatal.
    func save() {
        guard let url = Self.fileURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preferences)
            try data.write(to: url, options: .atomic)
            print("✅ PreferencesStore: saved preferences to \(url.path)")
        } catch {
            print("❌ PreferencesStore: failed to save preferences — \(error.localizedDescription)")
        }
    }
}
