//
//  WeekPlan.swift
//  Meal Seek
//
//  A persisted 7-day meal plan. Stores recipe IDs only — Recipes are looked up
//  in RecipeStore at render time. Monday-start week math lives here too.
//

import Foundation

/// One slot in a week: which recipes, for which meal, on which day.
///
/// A breakfast slot is a single recipe. A lunch or dinner slot offers a set of
/// same-cuisine CANDIDATES (4 where the pool allows) of which the user cooks one
/// or more, and to which the user may ADD dishes by hand from the whole library.
/// `selectedIDs` is the slot's real content: what the card lists, what the
/// grocery list buys, and what the 8-dish ceiling counts.
///
/// The two arrays mean different things, and the difference is what tells a
/// generator dish from a hand-picked one WITHOUT storing a per-dish source flag
/// (which would be a schema change):
///
/// - `candidateIDs` is the GENERATOR'S OFFER for this slot, fixed at generation
///   time and never grown by a manual add. Removing a selected candidate leaves
///   it here, so the offer survives the deselection and stays one tap away.
/// - `selectedIDs` is what gets cooked. An id in `selectedIDs` but NOT in
///   `candidateIDs` is by definition a manual add; removing it drops it from the
///   only array it was ever in, which is exactly the "remove from both" rule.
///
/// So `candidateIDs` stays bounded by the generator's own `candidatesPerSlot`,
/// `selectedIDs` by `PlanGenerator.maxSelectedDishes(for:)`, and neither can
/// grow without bound as the user adds and removes.
///
/// Selection is deliberately NOT clamped to the candidate set — that clamp is
/// what made a manual add impossible to represent. The non-empty guarantee
/// stays: an empty selection would silently drop the slot from the grocery
/// list, which is a data-loss bug rather than a display one.
///
/// `recipeID` survives as the slot's headline recipe — the first selected dish
/// — so the share card, feedback events, and every plan file written before
/// this feature keep reading one recipe per slot. It is always
/// `selectedIDs.first`; the initializer enforces that rather than trusting
/// callers, so the two can never drift.
struct PlannedMeal: Codable, Hashable {
    let recipeID: String
    /// "breakfast", "lunch", or "dinner".
    let mealType: String
    /// 0 = Monday … 6 = Sunday.
    let dayIndex: Int
    /// The generator's offer for this slot, in draw order. All share one
    /// cuisine. Breakfast is always exactly `[recipeID]`. Manual adds never
    /// land here — see the type comment.
    let candidateIDs: [String]
    /// The dishes the user will actually cook, in display order — never empty,
    /// never duplicated. Held as an array rather than a `Set` so encoding is
    /// deterministic (a `Set` would serialize in arbitrary order and churn the
    /// backup diff) and so a replace can preserve every other dish's position.
    let selectedIDs: [String]

    /// Defaults reproduce the pre-candidates shape exactly: one candidate, and
    /// it is selected. That is what keeps every existing call site — the
    /// generator's breakfast row, the picker, and the test harnesses — correct
    /// without passing the new arguments.
    ///
    /// Caller order of `selectedIDs` is preserved verbatim (minus duplicates).
    /// It used to be re-sorted into candidate order, which a manual add — not
    /// in `candidateIDs` at all — would have silently dropped.
    ///
    /// An EMPTY `candidateIDs` is legal and meaningful: it is a slot the
    /// generator never offered anything for, i.e. one the user filled by hand.
    /// Every dish in such a slot is a manual dish, which is what makes removing
    /// one delete it outright instead of leaving it re-selectable under an offer
    /// that was never made. Passing `nil` still means "no candidate set given",
    /// which reproduces the pre-candidates shape as `[recipeID]` — that is the
    /// path v1 plan files and backups decode through, and it is unchanged.
    ///
    /// Only `selectedIDs` carries a non-empty guarantee; an empty selection
    /// would silently drop the slot from the grocery list.
    init(recipeID: String, mealType: String, dayIndex: Int,
         candidateIDs: [String]? = nil, selectedIDs: [String]? = nil) {
        let candidates = candidateIDs ?? [recipeID]
        var seen = Set<String>()
        var selection = (selectedIDs ?? [recipeID]).filter { seen.insert($0).inserted }
        if selection.isEmpty {
            selection = [candidates.first ?? recipeID]
        }
        self.candidateIDs = candidates
        self.selectedIDs = selection
        self.recipeID = selection[0]
        self.mealType = mealType
        self.dayIndex = dayIndex
    }

    /// Whether the GENERATOR offered alternatives for this slot.
    ///
    /// Narrowed meaning, and currently unused. Under the candidate/selection
    /// split this reports only on the generator's offer — it is unaffected by
    /// anything the user adds or removes, and it is NOT "this slot has more than
    /// one dish" (that is `dishCount > 1`). Its former callers — routing a card
    /// tap to the selection sheet, the "Choose dishes" menu item, the "+n more"
    /// line and the "n / 4" capsule — were all superseded when the card began
    /// listing every dish by name. Retained rather than deleted; see
    /// PRE_LAUNCH.md, "Per-dish picker follow-ups".
    var offersChoice: Bool { candidateIDs.count > 1 }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    /// How many dishes this slot holds — the number the 8-dish ceiling counts
    /// and the number the meal card lists.
    var dishCount: Int { selectedIDs.count }

    /// Dishes the user added by hand: cooked, but never part of the generator's
    /// offer for this slot. Derived, not stored.
    var manualDishIDs: [String] { selectedIDs.filter { !candidateIDs.contains($0) } }

    /// Generator candidates the user has not selected — what the picker pins in
    /// its "FROM YOUR PLAN" section. Empty once every candidate is cooked.
    var unselectedCandidateIDs: [String] { candidateIDs.filter { !selectedIDs.contains($0) } }

    /// Whether one more dish fits under this meal type's ceiling.
    var acceptsMoreDishes: Bool {
        selectedIDs.count < PlanGenerator.maxSelectedDishes(for: mealType)
    }

    // MARK: Per-dish edits

    /// Swaps ONE dish for another, in place. Every other dish keeps its
    /// position, and `candidateIDs` is untouched — an outgoing generator dish
    /// stays on offer, an outgoing manual dish was never there to begin with.
    ///
    /// Returns `nil` when the edit is a no-op or would duplicate: `outgoingID`
    /// is not in the slot, or `incomingID` is already cooked in it.
    func replacingDish(_ outgoingID: String, with incomingID: String) -> PlannedMeal? {
        guard let index = selectedIDs.firstIndex(of: outgoingID) else { return nil }
        guard outgoingID != incomingID else { return nil }
        guard !selectedIDs.contains(incomingID) else { return nil }
        var updated = selectedIDs
        updated[index] = incomingID
        return PlannedMeal(recipeID: updated[0], mealType: mealType, dayIndex: dayIndex,
                           candidateIDs: candidateIDs, selectedIDs: updated)
    }

    /// Drops ONE dish. `candidateIDs` is untouched for the same reason as
    /// `replacingDish`, which is what implements the two removal rules at once.
    ///
    /// Returns `nil` when the dish is absent, or when it is the LAST one —
    /// emptying a slot is `WeekPlan.removeMeal`'s job, not a selection edit's,
    /// because an empty slot is represented by absence rather than by a slot
    /// with no dishes.
    func removingDish(_ id: String) -> PlannedMeal? {
        guard selectedIDs.contains(id), selectedIDs.count > 1 else { return nil }
        let updated = selectedIDs.filter { $0 != id }
        return PlannedMeal(recipeID: updated[0], mealType: mealType, dayIndex: dayIndex,
                           candidateIDs: candidateIDs, selectedIDs: updated)
    }

    /// Appends dishes, in the order given, skipping any already cooked here and
    /// stopping at this meal type's ceiling. Returns `nil` when nothing was
    /// added, so a caller can leave the plan — and `hasManualEdits` — alone.
    func addingDishes(_ ids: [String]) -> PlannedMeal? {
        let room = PlanGenerator.maxSelectedDishes(for: mealType) - selectedIDs.count
        guard room > 0 else { return nil }
        var updated = selectedIDs
        for id in ids where !updated.contains(id) {
            updated.append(id)
            if updated.count - selectedIDs.count == room { break }
        }
        guard updated.count > selectedIDs.count else { return nil }
        return PlannedMeal(recipeID: updated[0], mealType: mealType, dayIndex: dayIndex,
                           candidateIDs: candidateIDs, selectedIDs: updated)
    }

    /// The same slot with a different selection. Returns `nil` when `ids`
    /// selects nothing valid — the caller's cue to reject the edit rather than
    /// write an empty slot.
    func selecting(_ ids: [String]) -> PlannedMeal? {
        let valid = candidateIDs.filter { ids.contains($0) }
        guard !valid.isEmpty else { return nil }
        return PlannedMeal(recipeID: valid[0], mealType: mealType, dayIndex: dayIndex,
                           candidateIDs: candidateIDs, selectedIDs: valid)
    }
}

extension PlannedMeal {
    private enum CodingKeys: String, CodingKey {
        case recipeID, mealType, dayIndex, candidateIDs, selectedIDs
    }

    /// Migration for plan files and backups written before lunch/dinner held
    /// candidate sets: a slot with no `candidateIDs` decodes as a single
    /// candidate that is selected, so nothing is lost and nothing is empty.
    /// Filling that slot back out to 4 needs the recipe database, which a
    /// decoder does not have — `PlanMigrator` does that pass afterwards.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let recipeID = try container.decode(String.self, forKey: .recipeID)
        self.init(
            recipeID: recipeID,
            mealType: try container.decode(String.self, forKey: .mealType),
            dayIndex: try container.decode(Int.self, forKey: .dayIndex),
            candidateIDs: try container.decodeIfPresent([String].self, forKey: .candidateIDs),
            selectedIDs: try container.decodeIfPresent([String].self, forKey: .selectedIDs)
        )
    }
}

struct WeekPlan: Codable, Equatable {
    /// The Monday this week starts on, normalized to local midnight.
    let weekStartDate: Date
    var meals: [PlannedMeal]
    /// True once the user has hand-edited this week via the slot mutators.
    /// A freshly generated plan is always false.
    var hasManualEdits: Bool = false

    func meal(ofType mealType: String, onDay dayIndex: Int) -> PlannedMeal? {
        meals.first { $0.mealType == mealType && $0.dayIndex == dayIndex }
    }

    /// Fills the slot, replacing any meal already planned there.
    ///
    /// Replacing via the picker collapses the slot to the one chosen dish: the
    /// old candidate set belonged to the recipe being replaced, and keeping it
    /// would leave the user looking at three alternatives to a dish they just
    /// rejected. `candidateIDs` lets a caller supply a fresh set instead.
    mutating func setMeal(recipeID: String, ofType mealType: String, onDay dayIndex: Int,
                          candidateIDs: [String]? = nil, selectedIDs: [String]? = nil) {
        meals.removeAll { $0.mealType == mealType && $0.dayIndex == dayIndex }
        meals.append(PlannedMeal(recipeID: recipeID, mealType: mealType, dayIndex: dayIndex,
                                 candidateIDs: candidateIDs, selectedIDs: selectedIDs))
        hasManualEdits = true
    }

    /// Applies a new selection to an existing slot. No-op when the slot is
    /// absent or `ids` selects nothing valid — a slot never becomes empty
    /// through selection, only through `removeMeal`.
    @discardableResult
    mutating func setSelection(_ ids: [String], ofType mealType: String, onDay dayIndex: Int) -> Bool {
        guard let index = meals.firstIndex(where: { $0.mealType == mealType && $0.dayIndex == dayIndex }),
              let updated = meals[index].selecting(ids) else { return false }
        guard updated != meals[index] else { return true }
        meals[index] = updated
        hasManualEdits = true
        return true
    }

    // MARK: Per-dish edits
    //
    // These are the slot mutators the meal card's per-dish menu and the picker
    // drive. They exist alongside `setMeal` rather than replacing it: `setMeal`
    // still means "fill this whole slot", which is what the empty-slot
    // "+ Add meal" path genuinely wants, and its documented collapse is correct
    // there. Routing a per-dish edit through it is what dropped the other
    // dishes; these keep the slot's other dishes and their positions.

    /// Swaps one dish for another, leaving every other dish in place.
    /// No-op (returns false) when the slot is absent or the edit is a no-op.
    @discardableResult
    mutating func replaceDish(_ outgoingID: String, with incomingID: String,
                              ofType mealType: String, onDay dayIndex: Int) -> Bool {
        guard let index = meals.firstIndex(where: { $0.mealType == mealType && $0.dayIndex == dayIndex }),
              let updated = meals[index].replacingDish(outgoingID, with: incomingID) else { return false }
        meals[index] = updated
        hasManualEdits = true
        return true
    }

    /// Drops one dish. Removing the slot's LAST dish empties the slot entirely,
    /// because an empty slot is represented by absence — that is what makes the
    /// card fall back to its dashed "+ Add meal" state.
    @discardableResult
    mutating func removeDish(_ id: String, ofType mealType: String, onDay dayIndex: Int) -> Bool {
        guard let index = meals.firstIndex(where: { $0.mealType == mealType && $0.dayIndex == dayIndex }),
              meals[index].isSelected(id) else { return false }
        if let updated = meals[index].removingDish(id) {
            meals[index] = updated
        } else {
            meals.remove(at: index) // it was the last dish
        }
        hasManualEdits = true
        return true
    }

    /// Adds dishes to an existing slot, up to the meal type's ceiling.
    @discardableResult
    mutating func addDishes(_ ids: [String], ofType mealType: String, onDay dayIndex: Int) -> Bool {
        guard let index = meals.firstIndex(where: { $0.mealType == mealType && $0.dayIndex == dayIndex }),
              let updated = meals[index].addingDishes(ids) else { return false }
        meals[index] = updated
        hasManualEdits = true
        return true
    }

    /// Empties the slot. An empty slot is simply absent from `meals`.
    mutating func removeMeal(ofType mealType: String, onDay dayIndex: Int) {
        meals.removeAll { $0.mealType == mealType && $0.dayIndex == dayIndex }
        hasManualEdits = true
    }
}

extension WeekPlan {
    private enum CodingKeys: String, CodingKey {
        case weekStartDate, meals, hasManualEdits
    }

    /// Custom decoding only for backward compatibility: weekplans.json saved
    /// before `hasManualEdits` existed has no such key, and the synthesized
    /// decoder throws on a missing key even when the property declares a
    /// default. Missing key decodes as false. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStartDate = try container.decode(Date.self, forKey: .weekStartDate)
        meals = try container.decode([PlannedMeal].self, forKey: .meals)
        hasManualEdits = try container.decodeIfPresent(Bool.self, forKey: .hasManualEdits) ?? false
    }
}

extension Calendar {
    /// The Monday of the week containing `date`, at local midnight.
    ///
    /// Computed from the weekday number directly rather than via
    /// `dateInterval(of: .weekOfYear)`, whose start depends on the locale's
    /// `firstWeekday` (Sunday in the US). Correct across month and year
    /// boundaries and regardless of locale.
    func mondayOfWeek(containing date: Date) -> Date {
        let day = startOfDay(for: date)
        // Gregorian weekday: 1 = Sunday, 2 = Monday, … 7 = Saturday.
        let weekday = component(.weekday, from: day)
        let daysAfterMonday = (weekday + 5) % 7 // Monday → 0 … Sunday → 6
        guard let monday = self.date(byAdding: .day, value: -daysAfterMonday, to: day) else {
            return day
        }
        return startOfDay(for: monday)
    }
}
