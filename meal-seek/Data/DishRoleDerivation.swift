//
//  DishRoleDerivation.swift
//  Meal Seek
//
//  Proposes a `DishRole` for a user's own recipe from its ingredients, so the
//  Add Recipe form can PRE-SELECT a chip instead of asking a user to classify
//  their dinner cold. The user always confirms; nothing here decides anything
//  on its own. Same contract as `AllergenTable`, and the same shape.
//
//  WHAT THIS IS A PORT OF, AND WHAT IT DELIBERATELY IS NOT.
//
//  `tools/derive_dish_roles.py` assigns the role of every bundled recipe. It
//  has two halves. The first is TITLE_KEYS — roughly 460 hand-authored title
//  keys matched longest-key-first with span consumption, ~400 lines of it.
//  That half is NOT ported here, and should not be: those keys are authored
//  against the bundled corpus's dish names, so they would misfire on a user's
//  title far more often than they would fire correctly. "Mom's Sunday thing"
//  matches nothing, and something like "Rice Cake Tteokbokki" is exactly the
//  case the span-consumption rule exists to rescue in a corpus we control.
//
//  The second half is the STRUCTURAL PASS — the Python's `if not matched:`
//  branch, the one that runs when no title key fits. That is what a user's
//  recipe always lands on, and it is what this file is:
//
//      ingredients carry a grain or tuber staple  ->  all_in_one
//      otherwise                                  ->  main
//
//  The Python reports that branch as LOW confidence for a human to read. Here
//  the human reading it is the user, in front of a chip they can change, which
//  is the same safeguard by a different route.
//
//  KNOWN AND ACCEPTED LIMIT: this can only ever propose `main` or
//  `all_in_one`. `side` and `staple` are reachable in the Python only through
//  title keys, so a user adding a green salad or a pot of plain rice has to
//  change the chip themselves — and a homemade side dish defaults to `main`.
//  That is expected rather than a defect, but it is the thing to revisit if
//  beta testers' recipes skew toward sides. Logged in PRE_LAUNCH.md.
//
//  Matching is EXACT on the lowercased ingredient name, mirroring the Python's
//  `{i["name"].lower() for i in recipe["ingredients"]}` set intersection. It
//  deliberately does not do `AllergenTable`'s span consumption: these are whole
//  ingredient names, not substrings of them, so there is no shorter key to
//  wrongly match inside a longer one.
//

import Foundation

enum DishRoleDerivation {
    /// Grain and bread staples: the carbohydrate a dish is built on. A recipe
    /// listing one of these already carries its own base, which is what makes
    /// it a complete meal rather than something you serve rice beside.
    ///
    /// Ported verbatim from `GRAIN_STAPLES` in tools/derive_dish_roles.py.
    /// Keep the two in step — if a name is added there, add it here.
    static let grainStaples: Set<String> = [
        "arborio rice", "basmati rice", "bread", "brioche bread", "brown rice",
        "buckwheat", "bulgur", "chow mein noodles", "ciabatta", "ciabatta bread",
        "cooked jasmine rice", "cooked rice", "corn tortilla", "cornmeal",
        "couscous", "crusty bread", "egg noodles", "elbow macaroni",
        "english muffin", "farro", "flattened rice", "flour tortilla", "fusilli",
        "fusilli pasta", "glass noodles", "gluten-free spaghetti", "granola",
        "jasmine rice", "lasagna noodles", "orzo", "pappardelle", "pearl barley",
        "penne pasta", "pita", "pita bread", "polenta", "potato gnocchi", "quinoa",
        "ramen noodles", "rice", "rice cakes", "rice noodle", "rice noodles",
        "rolled oat", "rolled oats", "rye bread", "sandwich bread",
        "shortcrust pastry", "small pasta", "soba noodle", "soba noodles",
        "sourdough bread", "spaghetti", "sub roll", "udon noodle", "udon noodles",
        "wheat noodle", "wheat noodles", "wide rice noodle", "wonton wrapper",
        "ziti pasta",
    ]

    /// Tubers, kept apart from the grains because they carry a plate far less
    /// reliably — a potato in a curry is a vegetable in it, not the base under
    /// it. The Python downgrades confidence for exactly this reason; here they
    /// simply count, because the user sees and confirms the result either way.
    ///
    /// Ported verbatim from `TUBER_STAPLES`.
    static let tuberStaples: Set<String> = [
        "mashed potato", "potato", "sweet potato",
    ]

    /// Breading is NOT a staple, in either set: "all-purpose flour",
    /// "breadcrumbs" and "panko" are absent on purpose, so a schnitzel stays a
    /// `main` rather than becoming a complete meal. Recorded here because it
    /// looks like an omission and is not one.
    static func proposedRole(for ingredients: [Ingredient]) -> DishRole? {
        guard !ingredients.isEmpty else { return nil }
        let names = Set(ingredients.map { $0.name.lowercased() })
        let carriesStaple = !names.isDisjoint(with: grainStaples)
            || !names.isDisjoint(with: tuberStaples)
        return carriesStaple ? .allInOne : .main
    }
}
