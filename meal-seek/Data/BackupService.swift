//
//  BackupService.swift
//  Meal Seek
//
//  Builds a BackupArchive from the live stores (export) and applies one back
//  to them (restore). All decode/validation/filtering happens BEFORE any file
//  is written, so a malformed or partial backup can never leave half the app
//  restored. Recipe ids in the backup that no longer exist in the bundled
//  database are dropped from ratings and plans rather than failing the restore.
//
//  A struct holding references to the @Observable store classes: mutating the
//  stores updates the shared instances, so every screen reflects a restore
//  immediately without an app relaunch.
//

import Foundation

struct BackupService {
    let preferencesStore: PreferencesStore
    let ratingsStore: RatingsStore
    let planStore: WeekPlanStore
    let groceryStateStore: GroceryStateStore
    let weekContext: WeekContext
    /// The user's own recipes. Unlike the bundled set, these ARE written into
    /// the backup — this device holds the only copy.
    let userRecipeStore: UserRecipeStore
    /// The bundled recipe set — used to drop unknown ids and to regenerate a
    /// week that dropping emptied. Never written into the backup.
    let recipes: [Recipe]
    let recipeSchemaVersion: Int

    // MARK: Export

    /// Snapshots every store's current in-memory state into an envelope. Reads
    /// only user data — the recipe database is referenced by id, never embedded.
    func makeArchive(now: Date = Date()) -> BackupArchive {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        let plans = planStore.plannedWeekStarts.compactMap { planStore.plan(for: $0) }
        let grocery = groceryStateStore.boughtByWeek.keys.sorted().map { week in
            BackupArchive.GroceryWeekState(
                weekStartDate: week,
                boughtNames: (groceryStateStore.boughtByWeek[week] ?? []).sorted()
            )
        }

        return BackupArchive(
            formatVersion: BackupArchive.currentFormatVersion,
            appVersion: version,
            appBuild: build,
            createdAt: now,
            recipeSchemaVersion: recipeSchemaVersion,
            payload: BackupArchive.Payload(
                preferences: preferencesStore.preferences,
                ratings: ratingsStore.ratings,
                weekPlans: plans,
                groceryState: grocery,
                userRecipes: userRecipeStore.recipes
            )
        )
    }

    /// Encodes an archive with sorted keys + pretty printing and ISO-8601 dates.
    func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    /// Writes a backup to a uniquely-named temporary file and returns its URL.
    /// The caller shares it and deletes it once the share sheet dismisses.
    func writeTemporaryBackup(now: Date = Date()) throws -> URL {
        let data = try encode(makeArchive(now: now))
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(Self.fileName(for: now))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// `Meal-Seek-Backup-YYYY-MM-DD.json` — identifying and sortable.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Meal-Seek-Backup-\(formatter.string(from: date)).json"
    }

    // MARK: Restore — validation

    /// Confirms the data is a JSON Meal Seek backup of a recognized format with
    /// a payload, and decodes it. Changes nothing on disk. The confirmation
    /// dialog and the actual restore run off the returned archive.
    func validate(_ data: Data) -> Result<BackupArchive, BackupError> {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return .failure(.notJSON)
        }
        guard let version = dict["formatVersion"] as? Int else {
            return .failure(.unreadableFile)
        }
        // Only a FUTURE format is unreadable. Older ones are migrated on decode
        // (see BackupArchive.currentFormatVersion), so a backup taken before
        // candidate sets existed still imports.
        guard version <= BackupArchive.currentFormatVersion else {
            return .failure(.unrecognizedFormatVersion(version))
        }
        guard dict["payload"] is [String: Any] else {
            return .failure(.missingPayload)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(BackupArchive.self, from: data) else {
            return .failure(.unreadableFile)
        }
        return .success(archive)
    }

    // MARK: Restore — apply

    /// Everything a restore changed, for the completion message and for
    /// post-restore verification (addition #1's plan/grocery week consistency).
    struct RestoreSummary {
        let backupDate: Date
        let droppedRatingCount: Int
        let droppedMealCount: Int
        /// Dishes removed because they carry an allergen the restored
        /// preferences exclude. Separate from `droppedMealCount`: "your recipe
        /// is gone" and "you are allergic to this" are different sentences,
        /// and only one of them is a safety message.
        let removedUnsafeCount: Int
        let regeneratedWeekCount: Int
        let recipeSchemaMismatch: Bool
        /// Grocery weeks with no matching plan week after restore (anomalous).
        let orphanGroceryWeeks: [Date]
        /// Plan weeks with no grocery state — normal for an unshopped week;
        /// reported for completeness, not treated as an error.
        let planWeeksWithoutGrocery: [Date]
    }

    /// Applies a validated archive. Order: extract (missing keys → empty),
    /// drop unknown recipe ids, regenerate any emptied current/future week,
    /// THEN write the four stores. If a write fails partway, returns
    /// `.partialWrite` naming what was and wasn't written.
    func restore(_ archive: BackupArchive) -> Result<RestoreSummary, BackupError> {
        let calendar = Calendar.current
        let currentWeek = calendar.mondayOfWeek(containing: Date())

        // Missing keys decode as nil → treat as empty (predates-a-feature backups).
        //
        // Preferences are the exception, and deliberately so: "empty" for that
        // struct means no allergies, no cuisine scope, default servings, a
        // reset kitchen name and no pantry decisions, which a restore would
        // then write over the real ones with no way back. An absent key means
        // the backup has nothing to say, so the preferences already on the
        // device stand. See BackupArchive.preferences(fallingBackTo:).
        let restoredPreferences = archive.preferences(fallingBackTo: preferencesStore.preferences)
        let rawRatings = archive.payload.ratings ?? [:]
        let rawPlans = archive.payload.weekPlans ?? []
        let rawGrocery = archive.payload.groceryState ?? []
        let restoredUserRecipes = archive.payload.userRecipes ?? []

        // Validity is judged against the BUNDLED set plus the user recipes
        // this backup is about to restore — not the ones currently on disk.
        // Otherwise a restore onto a fresh install would drop every rating and
        // planned meal that points at a user recipe, moments before writing
        // that recipe back.
        let bundledRecipes = recipes.filter { !UserRecipeStore.isUserRecipe(id: $0.id) }
        let restoredPool = bundledRecipes + restoredUserRecipes
        let knownIDs = Set(restoredPool.map(\.id))

        // Ratings: drop entries for recipes no longer in the bundle.
        let filteredRatings = rawRatings.filter { knownIDs.contains($0.key) }
        let droppedRatingCount = rawRatings.count - filteredRatings.count

        // Plans: drop unknown-recipe meals; regenerate a current/future week if
        // dropping emptied a week that had meals (never resurrect a week the
        // user deliberately left empty, and never rewrite historical weeks).
        // Unsafe against the preferences THIS RESTORE WILL APPLY — which, when
        // the archive carries its own, are the archive's. The plans and the
        // preferences in one backup can disagree (a hand-edited file, one moved
        // between devices, or one written before a sweep ran), and this is the
        // only path that writes a plan, so it is the only place that can catch
        // it. Computed from the restored pool so a user recipe is checked too.
        let unsafeRecipeIDs = PlanEditor.unsafeRecipeIDs(
            carryingAny: restoredPreferences.allergens, in: restoredPool
        )

        var restoredPlans: [WeekPlan] = []
        var droppedMealCount = 0
        var removedUnsafeCount = 0
        var regeneratedWeekCount = 0
        for plan in rawPlans {
            let week = calendar.mondayOfWeek(containing: plan.weekStartDate)
            // Prune per DISH, not per slot: an unknown candidate is dropped
            // from the slot while its known siblings survive, so one stale id
            // no longer discards three good dishes. A slot whose every
            // candidate is unknown drops entirely, as before. The allergen pass
            // runs in the same transform — see PlanEditor.restoring, which is
            // where both live so they can be tested without this store graph.
            let restored = PlanEditor.restoring(
                plan: plan, knownIDs: knownIDs, unsafeRecipeIDs: unsafeRecipeIDs
            )
            let safeMeals = restored.meals
            droppedMealCount += restored.droppedUnknownCount
            removedUnsafeCount += restored.removedUnsafeCount

            if safeMeals.isEmpty, !plan.meals.isEmpty, week >= currentWeek {
                switch PlanGenerator.generate(
                    recipes: restoredPool,
                    preferences: restoredPreferences,
                    ratings: filteredRatings,
                    weekStartDate: week
                ) {
                case .success(let regenerated):
                    // A partial week here is fine — it still replaces the
                    // now-empty week with valid meals.
                    restoredPlans.append(regenerated.plan)
                    regeneratedWeekCount += 1
                case .failure:
                    // Regeneration couldn't produce anything (e.g. the restored
                    // preferences exclude every recipe). Keep the emptied week
                    // rather than resurrecting stale meals.
                    var updated = plan
                    updated.meals = safeMeals
                    restoredPlans.append(updated)
                }
            } else {
                var updated = plan
                updated.meals = safeMeals
                restoredPlans.append(updated)
            }
        }

        // A pre-candidates backup restores one dish per lunch/dinner slot; fill
        // those slots back out to a full same-cuisine set against the RESTORED
        // preferences, so the imported week behaves like a generated one. Only
        // current/future weeks are touched — history is left as it was.
        let hydrated = PlanMigrator.hydrating(
            plans: restoredPlans,
            recipes: restoredPool,
            preferences: restoredPreferences,
            currentWeekStart: currentWeek
        )
        if !hydrated.isEmpty {
            let byWeek = Dictionary(
                hydrated.map { (calendar.mondayOfWeek(containing: $0.weekStartDate), $0) },
                uniquingKeysWith: { _, last in last }
            )
            restoredPlans = restoredPlans.map {
                byWeek[calendar.mondayOfWeek(containing: $0.weekStartDate)] ?? $0
            }
            print("ℹ️ BackupService: filled candidate sets for \(hydrated.count) restored week(s).")
        }

        // Grocery bought-state: row-ids (name / name#family), not recipe ids —
        // no id filtering. Stale rows are reconciled lazily by the grocery list.
        var restoredGrocery: [Date: Set<String>] = [:]
        for entry in rawGrocery {
            restoredGrocery[calendar.mondayOfWeek(containing: entry.weekStartDate)] = Set(entry.boughtNames)
        }

        // Consistency check across the two week-keyed stores (addition #1).
        let planWeeks = Set(restoredPlans.map { calendar.mondayOfWeek(containing: $0.weekStartDate) })
        let groceryWeeks = Set(restoredGrocery.keys)
        let orphanGroceryWeeks = groceryWeeks.subtracting(planWeeks).sorted()
        let planWeeksWithoutGrocery = planWeeks.subtracting(groceryWeeks).sorted()
        if !orphanGroceryWeeks.isEmpty {
            print("⚠️ BackupService: \(orphanGroceryWeeks.count) grocery week(s) reference no restored plan week.")
        }
        if !planWeeksWithoutGrocery.isEmpty {
            print("ℹ️ BackupService: \(planWeeksWithoutGrocery.count) plan week(s) have no grocery state (normal for unshopped weeks).")
        }

        // All transforms done — nothing written yet. Now write the stores.
        // User recipes go first: everything after them may reference their
        // ids, so a failure here must stop before anything points at recipes
        // that aren't on disk. Grocery last; a mid-way failure names progress.
        do {
            try userRecipeStore.restore(restoredUserRecipes)
        } catch {
            return .failure(.partialWrite("couldn't write your own recipes; nothing was changed"))
        }
        do {
            try preferencesStore.restore(restoredPreferences)
        } catch {
            return .failure(.partialWrite("your own recipes were restored but preferences could not be written"))
        }
        do {
            try ratingsStore.restore(filteredRatings)
        } catch {
            return .failure(.partialWrite("preferences were restored but ratings could not be written"))
        }
        do {
            try planStore.restore(restoredPlans)
        } catch {
            return .failure(.partialWrite("preferences and ratings were restored but week plans could not be written"))
        }
        do {
            try groceryStateStore.restore(restoredGrocery)
        } catch {
            return .failure(.partialWrite("preferences, ratings, and plans were restored but grocery state could not be written"))
        }

        // Open on the current week, never a restored historical one (addition #4).
        weekContext.selectedDate = calendar.startOfDay(for: Date())

        return .success(RestoreSummary(
            backupDate: archive.createdAt,
            droppedRatingCount: droppedRatingCount,
            droppedMealCount: droppedMealCount,
            removedUnsafeCount: removedUnsafeCount,
            regeneratedWeekCount: regeneratedWeekCount,
            recipeSchemaMismatch: archive.recipeSchemaVersion != recipeSchemaVersion,
            orphanGroceryWeeks: orphanGroceryWeeks,
            planWeeksWithoutGrocery: planWeeksWithoutGrocery
        ))
    }
}
