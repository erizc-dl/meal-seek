//
//  SlotTemplates.swift
//  Meal Seek
//
//  THE ONE FILE that says how a composed lunch or dinner slot is shaped.
//
//  Retuning generation means editing this file and nothing else. No slot count
//  and no all-in-one ratio may live in PlanGenerator — that is the whole point
//  of the split, and it is why these values are plain stored constants with no
//  logic wrapped around them. The generator asks this table what a slot wants
//  and then goes and fills it.
//
//  WHY SWIFT RATHER THAN JSON. Every other tunable in this app that ships as
//  JSON is recipe data, loaded through RecipeStore from the app bundle. These
//  are not data; they are the generator's own parameters, and the eight
//  standalone harnesses in tests/ compile the app sources directly rather than
//  running inside a bundle. A JSON file would have to be located and threaded
//  through all eight runner scripts before a single check could read it, and a
//  malformed edit would surface as a runtime decode failure rather than as a
//  compile error. A Swift table is still one file to edit, and a typo in it
//  does not build.
//
//  BREAKFAST IS NOT HERE, deliberately. `template(cuisine:mealType:)` returns
//  nil for any meal type that is not in `PlanGenerator.multiDishMealTypes`,
//  which is the existing single source of truth for "which meal types compose".
//  A nil template is the generator's signal to take the single-dish path. This
//  file therefore cannot make breakfast composed even by accident, and making
//  breakfast composed later stays the same two-line change it already was.
//

import Foundation

/// How many dishes of each role one composed slot wants, plus how often that
/// slot should be built from a single all-in-one dish instead.
///
/// The counts describe a PLATE, not an offer: `staple: 1, main: 2, side: 1` is
/// rice, two dishes and a soup, which is four dishes cooked and shopped for.
struct SlotTemplate: Equatable {
    /// Carbohydrate bases — rice, bread, noodles. Realistically always 0 or 1.
    let staple: Int
    /// Centrepieces. More than one is what makes a shared rice table a rice
    /// table rather than a plated dinner.
    let main: Int
    /// Vegetable dishes, salads and soups.
    let side: Int

    /// The share of this cuisine's days at this meal type that compose from one
    /// all_in_one rather than from staple + main. 0…1.
    ///
    /// NOT derived from pool size, and it must never become so. Drawing
    /// uniformly from the corpus would put all_in_one at 73% globally and as
    /// high as 87% for a single cuisine (Italian dinner is 43 all_in_one against
    /// 7 mains), because a complete dish is the easy thing for a recipe author
    /// to write — not because dinner is usually one bowl. Letting supply decide
    /// would serve pasta-in-a-bowl six nights in seven and undo the reason this
    /// phase exists. The number below is an editorial claim about how a
    /// household actually eats, held independent of how many recipes happen to
    /// exist, and it is in config precisely because it is a first guess.
    let allInOneShare: Double

    /// Dishes on the staple + main path.
    var composedDishCount: Int { staple + main + side }

    /// Dishes on the all-in-one path. The all_in_one fills the staple and main
    /// positions TOGETHER — that is the rule that keeps plain rice from landing
    /// beside a rice bowl — so the plate is one dish plus the template's sides,
    /// however many mains the template asked for.
    var allInOneDishCount: Int { 1 + side }

    /// The most dishes this template can ever ask for, on either path. Must
    /// stay at or under `PlanGenerator.maxSelectedDishesPerSlot`, or a
    /// generated slot would be born over the ceiling the picker enforces;
    /// the week-generation harness asserts this for every template in the table.
    var maxDishCount: Int { max(composedDishCount, allInOneDishCount) }

    /// How many of `dayCount` days take the all-in-one path.
    ///
    /// A QUOTA, not a per-day coin flip. Rolling independently each day would
    /// let a 0.25 dinner share come out as zero all-in-one dinners one week and
    /// five the next; the share only describes the long run, and a user sees one
    /// week. Rounding a count and then shuffling which days get it makes "about
    /// two dinners a week are a one-bowl meal" true of every single week.
    func allInOneDayCount(outOf dayCount: Int) -> Int {
        guard dayCount > 0 else { return 0 }
        return min(dayCount, max(0, Int((Double(dayCount) * allInOneShare).rounded())))
    }
}

enum SlotTemplates {
    /// Cuisines whose lunch and dinner are shared, composed meals rather than
    /// a plated main. These are the four whose dinner wants two mains beside
    /// one staple — the rice table.
    static let composedCuisines: Set<String> = ["Chinese", "Japanese", "Korean", "Thai"]

    // MARK: The table
    //
    // Four rows, chosen by (is this a composed cuisine?, is this dinner?).
    // These are starting values, expected to be retuned after beta.

    /// Rice, two dishes, a soup. A one-bowl dinner (ramen, bibimbap, pad thai,
    /// a donburi) is a real but minority evening meal in these cuisines —
    /// roughly two nights in seven.
    static let composedDinner = SlotTemplate(staple: 1, main: 2, side: 1, allInOneShare: 0.25)

    /// Lunch in these cuisines genuinely is one bowl more often than not — a
    /// bento, a donburi, a bowl of noodles — so the all-in-one path leads.
    static let composedLunch = SlotTemplate(staple: 1, main: 1, side: 1, allInOneShare: 0.60)

    /// A plated dinner: a centrepiece and two vegetables. Held just under half
    /// on the all-in-one path so the composed plate stays the default reading
    /// of "dinner" while pasta, stew and casserole nights stay ordinary.
    ///
    /// `staple: 0` is INTERIM, and it is a data gap wearing a config value.
    /// Ten of the seventeen cuisines have no staple of their own, so a staple
    /// position sends them to the universal pool — which is the three rices.
    /// Rice is right for Japanese, Korean, Brazilian, Peruvian and Mexican, and
    /// defensible for American; it is wrong for French, Italian, Canadian and
    /// Argentinian, where White Fish Piccata arrived with a bowl of steamed
    /// rice beside it. That is the couscous-beside-a-Japanese-main mistake
    /// pointing the other way, and asking for no staple at all is the only fix
    /// available without new recipes. The real fix is authoring Western staples
    /// — garlic bread, roasted potatoes, buttered pasta as a SIDE dish — and is
    /// logged in PRE_LAUNCH.md. Put this back to 1 when they exist.
    static let defaultDinner = SlotTemplate(staple: 0, main: 1, side: 2, allInOneShare: 0.45)

    /// A sandwich, a salad bowl, a burrito, a slice. Lunch outside the composed
    /// cuisines is overwhelmingly one vessel. `staple: 0` for the same interim
    /// reason as `defaultDinner`.
    static let defaultLunch = SlotTemplate(staple: 0, main: 1, side: 1, allInOneShare: 0.70)

    /// One (cuisine, meal type) pair.
    struct Key: Hashable {
        let cuisine: String
        let mealType: String

        init(_ cuisine: String, _ mealType: String) {
            self.cuisine = cuisine
            self.mealType = mealType
        }
    }

    /// Per-cuisine overrides, consulted before the four rows above.
    ///
    /// Empty on purpose. Retuning a whole group is an edit to one of the four
    /// constants; retuning ONE cuisine is one line here, e.g.
    ///
    ///     Key("Indian", "dinner"): SlotTemplate(staple: 1, main: 1, side: 2,
    ///                                           allInOneShare: 0.30),
    ///
    /// This exists so a single awkward cuisine never becomes a reason to add a
    /// fifth group, or worse, a special case in the generator.
    static let overrides: [Key: SlotTemplate] = [:]

    /// What this slot wants, or nil for a meal type that does not compose.
    ///
    /// Nil is meaningful and is the only thing keeping breakfast on its
    /// single-dish path: the generator branches on the template's absence
    /// rather than on a hardcoded meal-type test.
    static func template(cuisine: String, mealType: String) -> SlotTemplate? {
        guard PlanGenerator.multiDishMealTypes.contains(mealType) else { return nil }
        if let override = overrides[Key(cuisine, mealType)] { return override }

        switch (composedCuisines.contains(cuisine), mealType == "dinner") {
        case (true, true): return composedDinner
        case (true, false): return composedLunch
        case (false, true): return defaultDinner
        case (false, false): return defaultLunch
        }
    }

    /// Every template the table can hand out, for the harness to hold to the
    /// ceiling invariant without enumerating cuisines it does not know about.
    static var allTemplates: [SlotTemplate] {
        [composedDinner, composedLunch, defaultDinner, defaultLunch] + overrides.values
    }
}
