//
//  WeekPlanStore.swift
//  Meal Seek
//
//  Loads and saves ALL week plans as a single JSON file in the app's Documents
//  directory, keyed by each plan's Monday start date. No UserDefaults,
//  SwiftData, or Core Data.
//

import Foundation

@Observable
final class WeekPlanStore {
    /// Every saved plan, keyed by its Monday start date (local midnight).
    private(set) var plans: [Date: WeekPlan] = [:]

    private static let fileName = "weekplans.json"

    init() {
        plans = Self.load()
    }

    /// The Mondays of every stored week, ascending.
    var plannedWeekStarts: [Date] {
        plans.keys.sorted()
    }

    func plan(for weekStart: Date) -> WeekPlan? {
        plans[Calendar.current.mondayOfWeek(containing: weekStart)]
    }

    func hasPlan(for weekStart: Date) -> Bool {
        plan(for: weekStart) != nil
    }

    /// Inserts or replaces the plan for its week and persists all plans.
    func save(_ plan: WeekPlan) {
        plans[Calendar.current.mondayOfWeek(containing: plan.weekStartDate)] = plan
        persist()
    }

    /// Absolute URL of the plans file in Documents, or nil if it can't be resolved.
    private static func fileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ WeekPlanStore: could not locate the Documents directory.")
            return nil
        }
        return documents.appendingPathComponent(fileName)
    }

    private static func load() -> [Date: WeekPlan] {
        guard let url = fileURL() else { return [:] }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ℹ️ WeekPlanStore: no week plans file yet — starting empty.")
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode([WeekPlan].self, from: data)
            // Re-key through the Monday helper so lookups stay consistent even
            // if the device's time zone changed since the plans were saved.
            var plans: [Date: WeekPlan] = [:]
            for plan in stored {
                plans[Calendar.current.mondayOfWeek(containing: plan.weekStartDate)] = plan
            }
            print("✅ WeekPlanStore: loaded \(plans.count) week plan(s) from \(url.path)")
            return plans
        } catch {
            print("❌ WeekPlanStore: failed to read \(url.path) — \(error.localizedDescription). Starting empty.")
            return [:]
        }
    }

    /// Re-reads all plans from disk into the in-memory dictionary. Used after a
    /// data restore so Home and the grocery list reflect the restored file
    /// without a relaunch.
    func reload() {
        plans = Self.load()
    }

    /// Fills candidate sets into any current/future slot saved before lunch and
    /// dinner offered a choice of dishes. Idempotent and cheap: an already
    /// migrated store finds nothing to change and writes nothing, so this is
    /// safe to call on every launch.
    @discardableResult
    func migrateCandidateSets(recipes: [Recipe], preferences: UserPreferences) -> Int {
        let updated = PlanMigrator.hydrating(
            plans: plannedWeekStarts.compactMap { plans[$0] },
            recipes: recipes,
            preferences: preferences,
            currentWeekStart: Calendar.current.mondayOfWeek(containing: Date())
        )
        guard !updated.isEmpty else { return 0 }
        for plan in updated {
            plans[Calendar.current.mondayOfWeek(containing: plan.weekStartDate)] = plan
        }
        persist()
        print("✅ WeekPlanStore: filled candidate sets for \(updated.count) week plan(s).")
        return updated.count
    }

    /// Every stored plan, ascending by week. The read side of the two recipe
    /// operations below: the delete confirmation counts with it before the
    /// user commits, and the removal itself works from it.
    var allPlans: [WeekPlan] {
        plannedWeekStarts.compactMap { plans[$0] }
    }

    /// How many planned dishes reference `recipeID`, across every week.
    /// Read-only — this is what lets the delete dialog say what it is about to
    /// do instead of promising it vaguely.
    func plannedDishCount(forRecipe recipeID: String) -> Int {
        PlanEditor.removingRecipe(id: recipeID, fromPlans: allPlans).removedMealCount
    }

    /// Strips `recipeID` out of every saved plan and persists.
    ///
    /// Called when a user deletes one of their own recipes. Without it the id
    /// stays in the plan file forever: it still counts against the 8-dish
    /// ceiling, and it blanks the whole slot when it happens to be that slot's
    /// headline dish. Same shape as `migrateCandidateSets` — nothing to change
    /// means nothing written.
    @discardableResult
    func removeRecipe(id recipeID: String) -> Int {
        let result = PlanEditor.removingRecipe(id: recipeID, fromPlans: allPlans)
        guard !result.updatedPlans.isEmpty else { return 0 }

        // A plan whose every meal was dropped stays as an empty week rather
        // than disappearing: an empty week is a real state the Home screen
        // renders, and removing the key would make it indistinguishable from a
        // week the user never planned.
        for plan in result.updatedPlans {
            plans[Calendar.current.mondayOfWeek(containing: plan.weekStartDate)] = plan
        }
        persist()
        print("✅ WeekPlanStore: removed \(result.removedMealCount) planned dish(es) "
              + "referencing \(recipeID) from \(result.updatedPlans.count) week(s).")
        return result.removedMealCount
    }

    /// Replaces every stored plan with `newPlans` and persists in one step,
    /// re-keying each through the Monday helper exactly as load() does. Throws
    /// on write failure so a restore can report a partial failure.
    func restore(_ newPlans: [WeekPlan]) throws {
        guard let url = Self.fileURL() else { throw BackupError.documentsUnavailable }
        var rekeyed: [Date: WeekPlan] = [:]
        for plan in newPlans {
            rekeyed[Calendar.current.mondayOfWeek(containing: plan.weekStartDate)] = plan
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sortedPlans = rekeyed.keys.sorted().compactMap { rekeyed[$0] }
        let data = try encoder.encode(sortedPlans)
        try data.write(to: url, options: .atomic)
        plans = rekeyed
    }

    /// Persist every plan to disk. Errors are reported, never fatal.
    private func persist() {
        guard let url = Self.fileURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let sortedPlans = plans.keys.sorted().compactMap { plans[$0] }
            let data = try encoder.encode(sortedPlans)
            try data.write(to: url, options: .atomic)
            print("✅ WeekPlanStore: saved \(sortedPlans.count) week plan(s) to \(url.path)")
        } catch {
            print("❌ WeekPlanStore: failed to save week plans — \(error.localizedDescription)")
        }
    }
}
