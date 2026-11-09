//
//  PlanGenerator.swift
//  Meal Seek
//
//  Pure local filter-and-shuffle plan generation. No AI, no network — runs
//  instantly and offline.
//

import Foundation

enum PlanGenerator {
    /// The three daily slots, in display order.
    static let mealTypes = ["breakfast", "lunch", "dinner"]

    /// Meal types that offer a choice of dishes. Breakfast is deliberately not
    /// one of them — one dish is a breakfast.
    static let multiDishMealTypes: Set<String> = ["lunch", "dinner"]

    /// How many dishes a lunch or dinner slot offers.
    static let candidatesPerSlot = 4

    /// The hard ceiling on how many dishes a multi-dish slot may hold: the 4 the
    /// generator offers plus 4 the user can add by hand.
    static let maxSelectedDishesPerSlot = 8

    /// The most dishes ONE trip through the picker may add. Replacing is 1-for-1
    /// and does not count against this, which is what lets a slot reach 8
    /// user-chosen dishes without a single session ever adding more than 4.
    static let maxManualAddsPerSession = 4

    /// The most dishes a slot of this meal type may hold.
    ///
    /// Breakfast returns 1 — the single-dish rule expressed as a number rather
    /// than as a hardcoded exclusion, so the picker, the meal card's "+ Add
    /// dish" row, and `PlannedMeal.addingDishes` all derive the same answer from
    /// one place. Making breakfast multi-dish later is a change to this function
    /// and `multiDishMealTypes` above it, and nothing else.
    static func maxSelectedDishes(for mealType: String) -> Int {
        multiDishMealTypes.contains(mealType) ? maxSelectedDishesPerSlot : 1
    }

    /// How many dishes the picker may add in one session for a slot that
    /// currently holds `currentDishCount`: the session budget, narrowed by
    /// whatever room is left under the meal type's ceiling.
    static func addBudget(for mealType: String, currentDishCount: Int) -> Int {
        max(0, min(maxManualAddsPerSession, maxSelectedDishes(for: mealType) - currentDishCount))
    }

    /// How many dishes are selected on a slot the generator could NOT compose.
    ///
    /// This used to govern every lunch and dinner slot, and was what kept a
    /// generated week's grocery list identical to the old single-recipe
    /// behaviour. It no longer does. A composed slot selects its whole plate —
    /// rice, two dishes and a soup is four dishes cooked and four dishes
    /// shopped for, and a composed meal that shops for one of them is not a
    /// meal. That change is deliberate and applies to NEWLY generated weeks
    /// only: `PlanMigrator` still preserves an existing slot's selection
    /// verbatim, so no plan that already exists changes what it buys.
    ///
    /// What survives here is the un-composable path — a cuisine that can field
    /// no main and no all_in_one, which is what a pool of the user's own
    /// (role-less) recipes looks like. That path is unchanged in every respect,
    /// including this.
    static let defaultSelectionCount = 1

    /// How much more likely a liked recipe is to be drawn than an unrated one.
    private static let likedWeight = 3.0

    /// A cuisine that could not field a full slot, recorded per meal type so
    /// the caller can report which pools are too thin rather than discovering
    /// it as a short sheet.
    struct CandidateShortfall: Equatable {
        let mealType: String
        let cuisine: String
        let available: Int
        /// The role whose position had to be dropped from the plate, or nil
        /// when the cuisine was simply too thin to fill the slot's OFFER.
        ///
        /// The two are different problems and are kept apart rather than
        /// merged. A cuisine with plenty of dishes can still be unable to field
        /// a side, and a cuisine with two dishes total is thin no matter what
        /// roles they carry. `available` counts whatever the row is about: the
        /// dishes reachable in that role including the universal pool, or the
        /// whole cuisine's pool for this meal type.
        var role: DishRole? = nil
    }

    /// Builds a randomized 7-day plan from the recipe pool, the user's
    /// preferences, and their recipe ratings. Allergen exclusion is absolute:
    /// a recipe sharing any allergen with the user's set is never planned,
    /// even if that leaves a meal type's pool empty (those slots are omitted).
    /// Deselected cuisines and disliked recipes are excluded too, but those
    /// filters relax — cuisines first, dislikes last — if honoring them would
    /// otherwise empty a pool.
    ///
    /// The selection algorithm is unchanged from earlier milestones; only how
    /// the outcome is reported changed. Instead of returning an empty or
    /// partial `WeekPlan` with no signal, it returns:
    /// - `.failure` when nothing at all could be planned (empty database,
    ///   filters exclude everything, or too few recipes to fill a single slot);
    /// - `.success` with a `nil` warning for a complete 21-slot week;
    /// - `.success` with a `WeekGenerationWarning` for a partial week — the
    ///   valid meals it *did* plan, plus which meal types were left empty.
    ///
    /// `databaseLoadFailureReason` lets a caller pass the recipe loader's own
    /// error text through to the diagnostic when the pool is empty because the
    /// database never loaded.
    static func generate(
        recipes: [Recipe],
        preferences: UserPreferences,
        ratings: [String: RecipeRating],
        weekStartDate: Date,
        databaseLoadFailureReason: String? = nil
    ) -> Result<WeekGenerationOutcome, WeekGenerationError> {
        // An empty pool means the bundled database never loaded — a hard
        // failure distinct from over-narrow filters (which leave `recipes`
        // populated but filter it down).
        guard !recipes.isEmpty else {
            let reason = databaseLoadFailureReason ?? "The recipe database loaded 0 recipes."
            return .failure(.databaseLoadFailed(underlying: reason))
        }

        let allergenSafe = RecipeFilter.allergenSafe(recipes, allergens: preferences.allergens)
        let eligible = RecipeFilter.inCuisines(allergenSafe, cuisines: preferences.cuisines)

        var meals: [PlannedMeal] = []
        var usedIDs = Set<String>()
        var shortfalls: [CandidateShortfall] = []
        // Meal types whose allergen-safe pool was empty, so no day could be
        // filled for them — the partial-week signal.
        var unfilledMealTypes: [String] = []

        for mealType in mealTypes {
            let safePool = allergenSafe.filter { $0.mealTypes.contains(mealType) }
            guard !safePool.isEmpty else {
                print("⚠️ PlanGenerator: no allergen-safe \(mealType) recipes — leaving \(mealType) slots empty this week.")
                unfilledMealTypes.append(mealType)
                continue
            }

            // A deselected cuisine never appears — unless the selection is too
            // narrow to fill this meal type at all, in which case the cuisine
            // filter relaxes silently rather than producing empty slots.
            var fullPool = eligible.filter { $0.mealTypes.contains(mealType) }
            if fullPool.isEmpty {
                print("⚠️ PlanGenerator: no selected-cuisine \(mealType) recipes — relaxing the cuisine filter for \(mealType).")
                fullPool = safePool
            }

            // Disliked recipes are excluded — unless that would leave nothing
            // to plan, in which case the dislike filter relaxes last, again
            // silently.
            var pool = fullPool.filter { ratings[$0.id] != .disliked }
            if pool.isEmpty {
                print("⚠️ PlanGenerator: every eligible \(mealType) recipe is disliked — relaxing the dislike filter for \(mealType).")
                pool = fullPool
            }

            // Lunch and dinner COMPOSE a plate from roles; breakfast stays
            // exactly one recipe.
            if multiDishMealTypes.contains(mealType) {
                // The universal pool crosses cuisine SELECTION, not merely
                // cuisine. A user who picked only Japanese still reaches
                // steamed rice, which is filed under Chinese — that is what
                // `isUniversal` is for, and narrowing it to the selected
                // cuisines would leave every staple-less cuisine with no staple
                // at all. It is drawn from `safePool` and from nothing less
                // filtered, so allergen exclusion still comes first and
                // absolutely; only the cuisine and dislike filters are the ones
                // this widens past.
                var universalPool = safePool.filter { $0.isUniversal && ratings[$0.id] != .disliked }
                if universalPool.isEmpty {
                    universalPool = safePool.filter(\.isUniversal)
                }

                let slots = candidateSlots(
                    mealType: mealType, pool: pool, universalPool: universalPool,
                    ratings: ratings, usedIDs: &usedIDs, shortfalls: &shortfalls
                )
                guard slots.contains(where: { !$0.plate.isEmpty }) else {
                    return .failure(.unknown(underlying: "Empty candidate pool for \(mealType) after filtering."))
                }
                for (dayIndex, slot) in slots.enumerated() where !slot.plate.isEmpty {
                    meals.append(PlannedMeal(
                        recipeID: slot.plate[0].id,
                        mealType: mealType,
                        dayIndex: dayIndex,
                        candidateIDs: slot.offer.map(\.id),
                        selectedIDs: slot.plate.map(\.id)
                    ))
                }
                continue
            }

            // Prefer recipes not yet used anywhere in this week's plan, then
            // fill the 7 days by cycling: with 7+ candidates every day is
            // unique; with fewer, repeats recur at the cycle length, so the
            // same recipe never lands on consecutive days (unless only one
            // recipe is eligible at all). Liked recipes are weighted to land
            // earlier in the draw but obey the same no-repeat cycling.
            let ordered = weightedShuffled(pool.filter { !usedIDs.contains($0.id) }, ratings: ratings)
                + weightedShuffled(pool.filter { usedIDs.contains($0.id) }, ratings: ratings)
            // Unreachable — `pool` was non-empty above — but guard the modulo
            // and index below so an unexpected empty pool reports loudly
            // instead of trapping.
            guard !ordered.isEmpty else {
                return .failure(.unknown(underlying: "Empty candidate pool for \(mealType) after filtering."))
            }
            for dayIndex in 0..<7 {
                let recipe = ordered[dayIndex % ordered.count]
                meals.append(PlannedMeal(recipeID: recipe.id, mealType: mealType, dayIndex: dayIndex))
                usedIDs.insert(recipe.id)
            }
        }

        let expected = mealTypes.count * 7

        // Nothing at all could be planned: separate over-narrow filters from a
        // pool that survived filtering but can't fill even one slot.
        if meals.isEmpty {
            if allergenSafe.isEmpty {
                return .failure(.noRecipesMatchFilters)
            }
            return .failure(.insufficientRecipes(needed: expected, available: allergenSafe.count))
        }

        let plan = WeekPlan(weekStartDate: weekStartDate, meals: meals)
        let warning = unfilledMealTypes.isEmpty
            ? nil
            : WeekGenerationWarning(
                unfilledMealTypes: unfilledMealTypes,
                plannedMealCount: meals.count,
                expectedMealCount: expected
              )
        return .success(WeekGenerationOutcome(plan: plan, warning: warning,
                                              candidateShortfalls: shortfalls))
    }

    /// One composed slot: the plate the generator cooked, and the offer it drew
    /// that plate from.
    ///
    /// `plate` is always a subset of `offer` — the standing slot invariant that
    /// tests/slot-invariant asserts. It holds by construction rather than by
    /// checking: the plate goes into the offer first and the top-up only ever
    /// adds to it, so the two cannot drift.
    private struct ComposedSlot {
        var plate: [Recipe]
        var offer: [Recipe]
    }

    /// The 7 daily slots for one multi-dish meal type.
    ///
    /// Each day draws ONE cuisine and COMPOSES that day's plate from it, by
    /// role, to the shape `SlotTemplates` gives for (cuisine, meal type). No
    /// slot count and no all-in-one ratio is decided here — this function asks
    /// the table and fills what it asks for, which is what keeps retuning a
    /// one-file edit.
    ///
    /// Mixing cuisines is not a fallback. The one exception is the universal
    /// pool — dishes flagged `isUniversal`, which is how a cuisine with no
    /// staple of its own reaches steamed rice. A dish outside that pool never
    /// crosses into another cuisine's slot.
    ///
    /// `pool` and `universalPool` are both already allergen-filtered by the
    /// caller, and every dish on every plate comes from one of them. That is
    /// what makes an unsafe recipe unreachable as a candidate rather than
    /// merely unselected — and it is why the filter runs BEFORE assignment.
    /// Filtering afterwards could empty a position that had a safe alternative
    /// sitting in the pool the whole time.
    private static func candidateSlots(
        mealType: String,
        pool: [Recipe],
        universalPool: [Recipe],
        ratings: [String: RecipeRating],
        usedIDs: inout Set<String>,
        shortfalls: inout [CandidateShortfall]
    ) -> [ComposedSlot] {
        var byCuisine: [String: [Recipe]] = [:]
        for recipe in pool { byCuisine[recipe.cuisine, default: []].append(recipe) }

        // Full cuisines in random order (variety across the week), then thin
        // ones largest-first so a fallback gives up as little choice as it can.
        let full = byCuisine.keys
            .filter { (byCuisine[$0]?.count ?? 0) >= candidatesPerSlot }
            .shuffled()
        let thin = byCuisine.keys
            .filter { (byCuisine[$0]?.count ?? 0) < candidatesPerSlot }
            .sorted {
                let left = byCuisine[$0]?.count ?? 0, right = byCuisine[$1]?.count ?? 0
                return left == right ? $0 < $1 : left > right
            }
        let rotation = full + thin
        guard !rotation.isEmpty else { return [] }

        // Which days each cuisine owns. The all-in-one quota is taken over a
        // cuisine's OWN days, not over the week: a week mixes cuisines and each
        // one carries its own share, so a Chinese Tuesday and an Italian
        // Thursday are decided separately.
        var daysByCuisine: [String: [Int]] = [:]
        for dayIndex in 0..<7 {
            daysByCuisine[rotation[dayIndex % rotation.count], default: []].append(dayIndex)
        }
        var allInOneDays = Set<Int>()
        for (cuisine, days) in daysByCuisine {
            guard let template = SlotTemplates.template(cuisine: cuisine, mealType: mealType) else { continue }
            allInOneDays.formUnion(days.shuffled().prefix(template.allInOneDayCount(outOf: days.count)))
        }

        var localShortfalls: [CandidateShortfall] = []
        var reported = Set<String>()
        defer { shortfalls += localShortfalls }

        var slots: [ComposedSlot] = []
        for dayIndex in 0..<7 {
            let cuisine = rotation[dayIndex % rotation.count]
            let cuisinePool = byCuisine[cuisine] ?? []

            var plate: [Recipe] = []
            if let template = SlotTemplates.template(cuisine: cuisine, mealType: mealType) {
                let composed = composePlate(
                    template: template,
                    preferAllInOne: allInOneDays.contains(dayIndex),
                    cuisinePool: cuisinePool, universalPool: universalPool,
                    ratings: ratings, usedIDs: usedIDs
                )
                plate = composed.plate
                // A dropped position is reported the way a thin cuisine already
                // is — once per cuisine and role, diagnostic only. The slot is
                // still valid, still allergen-safe, and still not empty; it is
                // simply one dish shorter than the template asked for.
                for drop in composed.dropped where reported.insert("\(cuisine)#\(drop.role.rawValue)").inserted {
                    print("⚠️ PlanGenerator: \(cuisine) has no \(drop.role.rawValue) left for \(mealType) "
                          + "after filtering and universal fallback — that position is dropped from the plate.")
                    localShortfalls.append(CandidateShortfall(
                        mealType: mealType, cuisine: cuisine,
                        available: drop.available, role: drop.role
                    ))
                }
            }

            // THE LAST RUNG OF THE LADDER. A cuisine that can field no
            // centrepiece — neither a main nor an all_in_one survived filtering
            // — composes nothing, and a plate of a staple and a salad is not a
            // dinner. It falls back to exactly what this generator did before
            // roles existed: a flat same-cuisine draw, one dish selected.
            //
            // This is not only a defensive path. A recipe the USER added decodes
            // with `role == .unassigned` (the field post-dates the recipes
            // already in a tester's user-recipes.json), so a user whose pool is
            // mostly their own recipes reaches this rung by design and still
            // gets a full week rather than an empty one.
            if plate.isEmpty {
                plate = Array(preferringUnused(cuisinePool, usedIDs: usedIDs, ratings: ratings)
                    .prefix(defaultSelectionCount))
            }
            guard !plate.isEmpty else {
                slots.append(ComposedSlot(plate: [], offer: []))
                continue
            }

            // The offer is the plate plus same-cuisine alternates, up to the
            // same `candidatesPerSlot` it has always been. The plate goes in
            // first, which is what makes `plate ⊆ offer` true by construction.
            // The top-up is same-cuisine only: a universal dish may join a plate
            // as a fallback for a position, but it is not an alternative the
            // slot offers on its own.
            var offer = plate
            let onPlate = Set(plate.map(\.id))
            if offer.count < candidatesPerSlot {
                offer += preferringUnused(cuisinePool.filter { !onPlate.contains($0.id) },
                                          usedIDs: usedIDs, ratings: ratings)
                    .prefix(candidatesPerSlot - offer.count)
            }

            if offer.count < candidatesPerSlot, reported.insert(cuisine).inserted {
                print("⚠️ PlanGenerator: \(cuisine) offers only \(cuisinePool.count) \(mealType) recipe(s) "
                      + "after filtering — that slot shows \(offer.count) of \(candidatesPerSlot) dishes.")
                localShortfalls.append(CandidateShortfall(
                    mealType: mealType, cuisine: cuisine, available: cuisinePool.count
                ))
            }

            usedIDs.formUnion(offer.map(\.id))
            slots.append(ComposedSlot(plate: plate, offer: offer))
        }
        return slots
    }

    /// One plate, filled role by role to the template's shape.
    ///
    /// Returns the dishes in PLATE ORDER — centrepiece, staple, sides, soup
    /// last — so `plate[0]` is the dish the meal is named after. That matters
    /// beyond display: `PlannedMeal` takes its headline `recipeID` from the
    /// first selected dish, and a Chinese dinner headlined "Steamed Brown Rice"
    /// would be wrong on the share card and in every feedback event.
    ///
    /// Also returns the positions it had to drop, so the caller can report them
    /// as shortfalls. A dropped position is never an error: the plate is short,
    /// not empty, and generation never fails over one.
    private static func composePlate(
        template: SlotTemplate,
        preferAllInOne: Bool,
        cuisinePool: [Recipe],
        universalPool: [Recipe],
        ratings: [String: RecipeRating],
        usedIDs: Set<String>
    ) -> (plate: [Recipe], dropped: [(role: DishRole, available: Int)]) {
        var blocked = Set<String>()
        var dropped: [(role: DishRole, available: Int)] = []

        /// The universal fallback ladder for ONE position.
        ///
        /// The cuisine's own pool is exhausted COMPLETELY before the universal
        /// pool is touched — repeating the cuisine's own side is preferred to
        /// borrowing a fresh one from elsewhere. Freshness orders within each
        /// pool, never across them.
        ///
        /// That ordering is deliberate and was got wrong once. Letting an
        /// unused universal dish outrank a repeated same-cuisine one reads as
        /// the better variety trade until you see what it plates: a German beet
        /// salad beside mapo tofu, because the Chinese sides were already spent
        /// on lunch. A repeated stir-fried bok choy is the better dinner. The
        /// cost is real and is paid by cuisines with few sides of their own —
        /// Italian has three, and will cycle them rather than reach for any of
        /// the nineteen universal ones — but a monotonous Italian dinner is
        /// still an Italian dinner.
        func draw(_ role: DishRole, rejecting reject: (Recipe) -> Bool = { _ in false }) -> Recipe? {
            let same = cuisinePool.filter { $0.role == role && !blocked.contains($0.id) && !reject($0) }
            let universal = universalPool.filter { $0.role == role && !blocked.contains($0.id) && !reject($0) }
            let tiers = [
                same.filter { !usedIDs.contains($0.id) },
                same,
                universal.filter { !usedIDs.contains($0.id) },
                universal,
            ]
            for tier in tiers {
                if let pick = weightedShuffled(tier, ratings: ratings).first {
                    blocked.insert(pick.id)
                    return pick
                }
            }
            dropped.append((
                role,
                cuisinePool.filter { $0.role == role }.count
                    + universalPool.filter { $0.role == role }.count
            ))
            return nil
        }

        // The quota proposes, availability disposes. Deciding the path up front
        // — rather than trying one and backing out — is what keeps a staple
        // drawn for an abandoned path from ever reaching the plate.
        let hasAllInOne = cuisinePool.contains { $0.role == .allInOne }
        let hasMain = cuisinePool.contains { $0.role == .main }
            || universalPool.contains { $0.role == .main }
        guard hasAllInOne || hasMain else { return ([], []) }
        let useAllInOne = (preferAllInOne && hasAllInOne) || !hasMain

        var plate: [Recipe] = []
        if useAllInOne {
            // An all_in_one fills the staple and main positions TOGETHER, so no
            // staple is drawn on this path at all. That is the structural reason
            // plain rice can never land beside a rice bowl — there is no code
            // path that draws both, rather than a check performed afterwards
            // that someone could forget to run.
            if let dish = draw(.allInOne) { plate.append(dish) }
        } else {
            for _ in 0..<template.main { if let dish = draw(.main) { plate.append(dish) } }
            for _ in 0..<template.staple { if let dish = draw(.staple) { plate.append(dish) } }
        }
        guard !plate.isEmpty else { return ([], dropped) }

        // NO TWO SOUPS IN ONE SLOT — the whole reason `isSoup` exists. Once one
        // is plated, soups are rejected from the remaining side positions; if
        // soups are all that is left, the position drops rather than doubling up.
        var sides: [Recipe] = []
        var hasSoup = false
        for _ in 0..<template.side {
            guard let side = draw(.side, rejecting: { hasSoup && $0.isSoup }) else { break }
            sides.append(side)
            hasSoup = hasSoup || side.isSoup
        }
        // A soup closes a meal, so it sits last among the sides.
        plate += sides.filter { !$0.isSoup } + sides.filter(\.isSoup)

        return (plate, dropped)
    }

    /// `recipes` ordered so dishes this week has not used yet come first, each
    /// half weighted so liked recipes land early within it. A week therefore
    /// repeats a dish only once the pool it is drawing from runs out of fresh
    /// ones.
    private static func preferringUnused(
        _ recipes: [Recipe], usedIDs: Set<String>, ratings: [String: RecipeRating]
    ) -> [Recipe] {
        weightedShuffled(recipes.filter { !usedIDs.contains($0.id) }, ratings: ratings)
            + weightedShuffled(recipes.filter { usedIDs.contains($0.id) }, ratings: ratings)
    }

    /// A random permutation where liked recipes are `likedWeight`× as likely
    /// to land early (Efraimidis–Spirakis weighted sampling): each recipe
    /// draws the key random^(1/weight) and the list sorts by key descending.
    private static func weightedShuffled(_ recipes: [Recipe], ratings: [String: RecipeRating]) -> [Recipe] {
        recipes
            .map { recipe -> (recipe: Recipe, key: Double) in
                let weight = ratings[recipe.id] == .liked ? likedWeight : 1.0
                return (recipe, pow(Double.random(in: 0..<1), 1.0 / weight))
            }
            .sorted { $0.key > $1.key }
            .map(\.recipe)
    }
}
