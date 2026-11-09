//
//  PlanEditor.swift
//  Meal Seek
//
//  Pure plan-mutation logic for preference changes, kept out of the views so
//  it can be tested directly. Currently: the allergen safety sweep.
//

import Foundation

enum PlanEditor {
    /// A slot rebuilt to hold only the dishes that passed a keep-test.
    struct PrunedMeal {
        /// The surviving slot, or nil when NO dish in it survived — the
        /// caller's cue to drop the slot entirely.
        let meal: PlannedMeal?
        /// Dishes dropped: generated candidates and hand-added dishes alike.
        let removedDishCount: Int
    }

    /// Rebuilds one slot from the dishes satisfying `isKept`.
    ///
    /// Shared deliberately by the two callers that prune a plan against a set of
    /// ids — the allergen sweep below (`isKept` = "carries none of the new
    /// allergen") and `BackupService`'s restore pruner ("still exists in the
    /// recipe database"). They are the same algorithm with an inverted
    /// predicate, and they had drifted into two copies; keeping one
    /// implementation is what stops them disagreeing about hand-added dishes,
    /// in the same spirit as the single shared `GroceryListBuilder.aggregate`.
    ///
    /// A hand-added dish lives only in `selectedIDs`, so it is counted and kept
    /// separately from the generator's offer. The slot survives on ANY dish that
    /// passes — a surviving hand-added dish keeps it alive even when every
    /// generated candidate failed.
    static func pruning(_ meal: PlannedMeal, keeping isKept: (String) -> Bool) -> PrunedMeal {
        let keptCandidates = meal.candidateIDs.filter(isKept)
        let keptSelection = meal.selectedIDs.filter(isKept)

        let survivingManual = keptSelection.filter { !meal.candidateIDs.contains($0) }
        let removed = (meal.candidateIDs.count - keptCandidates.count)
            + (meal.manualDishIDs.count - survivingManual.count)

        guard let headline = keptSelection.first ?? keptCandidates.first else {
            return PrunedMeal(meal: nil, removedDishCount: removed)
        }
        return PrunedMeal(
            meal: PlannedMeal(
                recipeID: headline,
                mealType: meal.mealType,
                dayIndex: meal.dayIndex,
                // Passed through even when empty. If the whole generated offer
                // failed the keep-test then nothing generated survived, so the
                // dish still cooking here is by definition a hand-added one —
                // and standing it in as a candidate would misfile it as an offer
                // the generator made, leaving it re-selectable after a removal.
                candidateIDs: keptCandidates,
                // Never an empty selection: a slot with no dishes would vanish
                // from the grocery list while still occupying the card.
                selectedIDs: keptSelection.isEmpty ? [headline] : keptSelection
            ),
            removedDishCount: removed
        )
    }

    struct AllergenSweepResult {
        /// The current/future plans that changed, with unsafe recipes removed.
        /// Plans that contained no unsafe recipe are not included.
        let updatedPlans: [WeekPlan]
        /// Total DISHES removed across all updated plans — an unselected
        /// candidate counts, because it was still one tap from being cooked.
        let removedMealCount: Int
    }

    /// Every recipe carrying ANY of `allergens`. The one definition of
    /// "unsafe", shared by the sweep below and by the restore path, so the two
    /// cannot come to different answers about the same dish.
    static func unsafeRecipeIDs(carryingAny allergens: Set<String>, in recipes: [Recipe]) -> Set<String> {
        guard !allergens.isEmpty else { return [] }
        return Set(recipes.filter { !allergens.isDisjoint(with: $0.allergens) }.map(\.id))
    }

    /// The safety rule for ONE newly added allergen — the settings screen's
    /// case. A thin wrapper: the set-based version below is the real
    /// implementation, so there is one sweep, not two.
    static func removingMeals(
        containingAllergen allergen: String,
        fromPlans plans: [WeekPlan],
        recipes: [Recipe],
        currentWeekStart: Date
    ) -> AllergenSweepResult {
        removingMeals(containingAnyAllergen: [allergen], fromPlans: plans,
                      recipes: recipes, currentWeekStart: currentWeekStart)
    }

    /// The safety rule for a WHOLE allergen set: remove every dish carrying any
    /// of them from the current week and all future weeks. Past weeks
    /// (weekStartDate < currentWeekStart) are historical and are never touched.
    ///
    /// A lunch/dinner slot is pruned rather than emptied: an unsafe recipe is
    /// stripped from BOTH `selectedIDs` and `candidateIDs`, so it cannot be
    /// re-selected from the sheet afterwards. The slot survives on its
    /// remaining same-cuisine candidates, and only empties when every candidate
    /// was unsafe. Nothing is ever substituted in.
    ///
    /// Set-based rather than per-allergen because the restore path has a whole
    /// `UserPreferences.allergens` to enforce at once. Running the
    /// single-allergen version once per allergen would mean merging N partial
    /// result sets — `updatedPlans` carries only the plans that CHANGED — and
    /// that merge is exactly where a plan goes missing.
    static func removingMeals(
        containingAnyAllergen allergens: Set<String>,
        fromPlans plans: [WeekPlan],
        recipes: [Recipe],
        currentWeekStart: Date
    ) -> AllergenSweepResult {
        let unsafeRecipeIDs = unsafeRecipeIDs(carryingAny: allergens, in: recipes)
        guard !unsafeRecipeIDs.isEmpty else {
            return AllergenSweepResult(updatedPlans: [], removedMealCount: 0)
        }

        var updatedPlans: [WeekPlan] = []
        var removedMealCount = 0
        for plan in plans {
            let weekStart = Calendar.current.mondayOfWeek(containing: plan.weekStartDate)
            guard weekStart >= currentWeekStart else { continue }

            var safeMeals: [PlannedMeal] = []
            var removedHere = 0
            for meal in plan.meals {
                let pruned = pruning(meal) { !unsafeRecipeIDs.contains($0) }
                removedHere += pruned.removedDishCount
                if let safe = pruned.meal { safeMeals.append(safe) }
            }
            guard removedHere > 0 else { continue }

            removedMealCount += removedHere
            var updated = plan
            updated.meals = safeMeals
            updatedPlans.append(updated)
        }
        return AllergenSweepResult(updatedPlans: updatedPlans, removedMealCount: removedMealCount)
    }
}

extension PlanEditor {
    /// One restored week, after both of the tests a restore has to apply.
    struct RestoredPlan {
        let meals: [PlannedMeal]
        /// Dishes dropped because the recipe no longer exists.
        let droppedUnknownCount: Int
        /// Dishes removed because they carry an allergen the RESTORED
        /// preferences exclude. Counted apart from the above because the two
        /// are different things to tell a user.
        let removedUnsafeCount: Int
    }

    /// The plan transform a restore applies to one week.
    ///
    /// Lives here rather than inside `BackupService` because `BackupService`
    /// holds five `@Observable` stores and therefore cannot be driven by the
    /// standalone harnesses at all — which is precisely how it came to be the
    /// one path that writes a plan without ever consulting the allergen set.
    /// This file's whole purpose is that plan mutations can be tested directly.
    ///
    /// Two passes rather than one combined predicate, so the counts stay
    /// attributable: a dish dropped because its recipe is gone and a dish
    /// removed because the user is allergic to it are different sentences.
    /// Both passes go through the shared `pruning`, so hand-added dishes are
    /// treated identically in each.
    static func restoring(
        plan: WeekPlan,
        knownIDs: Set<String>,
        unsafeRecipeIDs: Set<String>
    ) -> RestoredPlan {
        var meals: [PlannedMeal] = []
        var droppedUnknown = 0
        var removedUnsafe = 0

        for meal in plan.meals {
            let known = pruning(meal) { knownIDs.contains($0) }
            droppedUnknown += known.removedDishCount
            guard let survivingKnown = known.meal else { continue }

            // The allergen pass. It runs on the survivors of the first pass so
            // a dish is never counted under both reasons, and it strips unsafe
            // ids from candidateIDs as well as selectedIDs — leaving one in the
            // offer would put it one tap from being cooked again.
            let safe = pruning(survivingKnown) { !unsafeRecipeIDs.contains($0) }
            removedUnsafe += safe.removedDishCount
            guard let survivingSafe = safe.meal else { continue }

            meals.append(survivingSafe)
        }

        return RestoredPlan(meals: meals,
                            droppedUnknownCount: droppedUnknown,
                            removedUnsafeCount: removedUnsafe)
    }

    /// Every plan with one recipe stripped out of it — the deletion rule.
    ///
    /// Deleting a user recipe must not leave its id behind in a saved plan: a
    /// stale id still counts against the 8-dish ceiling, and blanks the whole
    /// slot when it happens to be that slot's headline dish. (The grocery list
    /// is already correct without this — it resolves ids against the recipe
    /// pool on every render, so an unresolvable one contributes nothing.)
    ///
    /// Unlike the allergen sweep this touches EVERY week, past ones included.
    /// A historical week is a record of what was cooked, but a dangling id is
    /// not a record of anything — it renders as a hole either way, and leaving
    /// it there is what accumulates.
    static func removingRecipe(
        id deletedID: String,
        fromPlans plans: [WeekPlan]
    ) -> AllergenSweepResult {
        var updatedPlans: [WeekPlan] = []
        var removedCount = 0

        for plan in plans {
            var keptMeals: [PlannedMeal] = []
            var removedHere = 0
            for meal in plan.meals {
                let pruned = pruning(meal) { $0 != deletedID }
                removedHere += pruned.removedDishCount
                if let kept = pruned.meal { keptMeals.append(kept) }
            }
            guard removedHere > 0 else { continue }

            removedCount += removedHere
            var updated = plan
            updated.meals = keptMeals
            updatedPlans.append(updated)
        }
        return AllergenSweepResult(updatedPlans: updatedPlans, removedMealCount: removedCount)
    }
}
