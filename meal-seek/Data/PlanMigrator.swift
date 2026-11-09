//
//  PlanMigrator.swift
//  Meal Seek
//
//  Second half of the candidate-set migration. `PlannedMeal.init(from:)` can
//  make an old one-recipe slot decode losslessly — it becomes a single selected
//  candidate — but it cannot fill that slot back out to four, because a decoder
//  has no recipe database and no user preferences. This does that pass, at the
//  one point where both are available.
//
//  Idempotent: a slot already holding a full candidate set is returned
//  untouched, so running it on every launch costs nothing and cannot drift.
//

import Foundation

enum PlanMigrator {
    /// Plans that gained candidates, ready to persist. Plans already migrated
    /// (and past weeks, which are historical and read-only) are not included,
    /// so an unchanged launch writes nothing.
    static func hydrating(
        plans: [WeekPlan],
        recipes: [Recipe],
        preferences: UserPreferences,
        currentWeekStart: Date
    ) -> [WeekPlan] {
        // Allergen exclusion first and unconditionally: a recipe the user
        // cannot eat must never become a candidate, and migration is exactly
        // the path where that would otherwise slip through, because the slot
        // being filled predates the current allergen set.
        let safe = RecipeFilter.allergenSafe(recipes, allergens: preferences.allergens)
        let byID = Dictionary(safe.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var updated: [WeekPlan] = []
        for plan in plans {
            let weekStart = Calendar.current.mondayOfWeek(containing: plan.weekStartDate)
            guard weekStart >= currentWeekStart else { continue }
            guard let hydrated = hydrating(plan: plan, safe: safe, byID: byID) else { continue }
            updated.append(hydrated)
        }
        return updated
    }

    /// One plan, or nil when nothing needed filling.
    private static func hydrating(
        plan: WeekPlan,
        safe: [Recipe],
        byID: [String: Recipe]
    ) -> WeekPlan? {
        // Recipes already spoken for anywhere in this week, so a backfilled
        // candidate prefers a dish the week does not already contain. Counts
        // hand-added dishes too: one the user chose on Tuesday is not a "fresh"
        // pick for Thursday just because no generator offered it.
        var usedIDs = Set(plan.meals.flatMap(\.candidateIDs))
            .union(plan.meals.flatMap(\.selectedIDs))
        var changed = false
        var meals: [PlannedMeal] = []

        for meal in plan.meals {
            guard PlanGenerator.multiDishMealTypes.contains(meal.mealType),
                  meal.candidateIDs.count < PlanGenerator.candidatesPerSlot,
                  // The slot's cuisine comes from the recipe already in it. An
                  // id no longer in the database (a deleted user recipe) leaves
                  // the slot exactly as it is rather than guessing a cuisine.
                  let anchor = meal.candidateIDs.compactMap({ byID[$0] }).first
            else {
                meals.append(meal)
                continue
            }

            let needed = PlanGenerator.candidatesPerSlot - meal.candidateIDs.count
            let pool = safe.filter {
                $0.cuisine == anchor.cuisine
                    && $0.mealTypes.contains(meal.mealType)
                    && !meal.candidateIDs.contains($0.id)
                    // A dish the user added by hand must never be backfilled
                    // INTO the offer. It lives in selectedIDs alone, and that is
                    // what marks it as hand-added; adopting it as a candidate
                    // would refile a deliberate choice as a suggestion, so
                    // removing it later would leave it re-selectable under an
                    // offer the generator never made.
                    && !meal.selectedIDs.contains($0.id)
            }
            // Dishes this week does not already use come first; the rest fill in
            // only when the cuisine is too thin to avoid a repeat.
            let fresh = pool.filter { !usedIDs.contains($0.id) }.shuffled()
            let reused = pool.filter { usedIDs.contains($0.id) }.shuffled()
            let additions = Array((fresh + reused).prefix(needed)).map(\.id)
            guard !additions.isEmpty else {
                meals.append(meal)
                continue
            }

            usedIDs.formUnion(additions)
            changed = true
            // Selection is preserved exactly: the recipe the user had planned
            // stays the one selected dish, so migrating never changes what the
            // grocery list buys.
            meals.append(PlannedMeal(
                recipeID: meal.recipeID,
                mealType: meal.mealType,
                dayIndex: meal.dayIndex,
                candidateIDs: meal.candidateIDs + additions,
                selectedIDs: meal.selectedIDs
            ))
        }

        guard changed else { return nil }
        var result = plan
        result.meals = meals
        // Not a manual edit: the user did not choose this, the migration did.
        return result
    }
}
