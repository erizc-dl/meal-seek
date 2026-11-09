//
//  BackupArchive.swift
//  Meal Seek
//
//  The single versioned envelope written by the "Back up data" flow and read
//  by "Restore from backup". Holds USER data only — never the bundled
//  647-recipe database, which ships in the app; recipes are referenced by id.
//  The recipe database's own schemaVersion is recorded so a restore can tell a
//  backup was made against a different recipe set.
//
//  Encoded with a single JSONEncoder using `.iso8601` dates (covering the
//  envelope's createdAt AND every nested weekStartDate) and
//  `[.prettyPrinted, .sortedKeys]` so the file is human-readable and diffable.
//

import Foundation

struct BackupArchive: Codable {
    /// Bumped when the persisted shape changes. A restore refuses versions from
    /// the FUTURE only (see BackupService.validate) — older ones are migrated.
    ///
    /// 1 → 2: lunch/dinner slots gained `candidateIDs`/`selectedIDs`. A v1 slot
    /// decodes as one candidate that is selected (`PlannedMeal.init(from:)`),
    /// and `PlanMigrator` fills it back out to a full set afterwards, so a v1
    /// backup restores with no data loss and no empty slot.
    static let currentFormatVersion = 2

    let formatVersion: Int
    /// App version/build that produced the file (CFBundleShortVersionString /
    /// CFBundleVersion), for diagnostics — not used to gate a restore.
    let appVersion: String
    let appBuild: String
    /// When the backup was written (shown in the restore confirmation dialog).
    let createdAt: Date
    /// schemaVersion of the recipe database this backup was made against.
    /// A mismatch is surfaced, not fatal — unknown recipe ids are dropped.
    let recipeSchemaVersion: Int
    /// Each store's data under a named key. Every field is optional so a backup
    /// that predates a feature (e.g. no `ratings`) still restores, treating the
    /// missing data as empty.
    let payload: Payload

    struct Payload: Codable {
        var preferences: UserPreferences?
        var ratings: [String: RecipeRating]?
        var weekPlans: [WeekPlan]?
        var groceryState: [GroceryWeekState]?
        /// The user's own recipes, in full. Unlike every other field here,
        /// these are recipe RECORDS rather than references — a user recipe
        /// exists nowhere but this device, so omitting it would make a restore
        /// destroy the only copy. Bundled recipes are still never included.
        var userRecipes: [Recipe]?
    }

    /// One week's bought grocery rows. `boughtNames` holds grocery row-ids —
    /// bare ingredient names, or "name#family" for unit-split rows — NOT recipe
    /// ids, so they are never matched against the recipe database on restore.
    struct GroceryWeekState: Codable {
        let weekStartDate: Date
        let boughtNames: [String]
    }
}

/// Everything that can go wrong reading or applying a backup, with
/// user-facing copy for the failure alert.
enum BackupError: LocalizedError {
    case notJSON
    case unreadableFile
    case unrecognizedFormatVersion(Int)
    case missingPayload
    case documentsUnavailable
    /// A write failed after one or more stores were already updated. The
    /// associated string names what did and didn't get written.
    case partialWrite(String)

    var errorDescription: String? {
        switch self {
        case .notJSON:
            return String(localized: "This file isn't a Meal Seek backup — it couldn't be read as JSON.")
        case .unreadableFile:
            return String(localized: "This file couldn't be read as a Meal Seek backup. Nothing was changed.")
        case .unrecognizedFormatVersion(let version):
            return String(localized: "This backup was made by a newer version of Meal Seek (format \(version)) and can't be read. Nothing was changed.")
        case .missingPayload:
            return String(localized: "This backup is missing its data and couldn't be restored. Nothing was changed.")
        case .documentsUnavailable:
            return String(localized: "Meal Seek couldn't access its storage to write the restored data.")
        case .partialWrite(let detail):
            return String(localized: "The restore failed partway through: \(detail). Please try restoring the backup again.")
        }
    }
}

extension BackupArchive {
    /// The preferences a restore should actually apply, given what is already
    /// on the device.
    ///
    /// `payload.preferences` is optional so a backup predating the preferences
    /// key still restores. The question this answers is what an ABSENT key
    /// means, and the answer is emphatically not "the defaults": every field on
    /// `UserPreferences` has a default, so substituting a fresh one silently
    /// discards the user's allergies, cuisine scope, servings, kitchen name,
    /// pantry decisions and onboarding state in a single write — and a restore
    /// is not undoable. An absent key means the backup has nothing to say about
    /// preferences, so the right move is to leave the ones already set alone.
    ///
    /// A backup that DOES carry preferences still replaces them wholesale —
    /// that is what a restore is, and the confirmation dialog says so.
    func preferences(fallingBackTo existing: UserPreferences) -> UserPreferences {
        payload.preferences ?? existing
    }
}
