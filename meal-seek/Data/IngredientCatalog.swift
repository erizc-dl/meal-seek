//
//  IngredientCatalog.swift
//  Meal Seek
//
//  The canonical ingredient-name index behind Add Recipe's suggestion
//  dropdown. Two sources, one list:
//
//  1. Every distinct `Ingredient.name` in the bundled 676 recipes (335 names).
//     Picking one of these is what makes a user recipe's ingredient CONSOLIDATE
//     with built-in recipes in the grocery list — same string, same row.
//  2. `suggestionOnlyStaples` below: common pantry items no bundled recipe
//     happens to use. They feed the dropdown and the allergen table only; no
//     bundled recipe references them and no recipe data changes because of them.
//
//  Suggestions never autofill. The user's typed text is authoritative and is
//  never overwritten — tapping a suggestion is the only way a canonical string
//  is adopted. A name with no match saves exactly as typed; it simply may list
//  on its own row in the grocery list, which is fine.
//
//  Everything here is local and in-memory: built once from already-loaded
//  recipes, no network, no I/O per keystroke.
//

import Foundation

struct IngredientCatalog {
    /// Every suggestible name, alphabetical, aliases already collapsed.
    let names: [String]

    /// Bundled-recipe usage count per name, used to rank suggestions so the
    /// ingredient that consolidates with the most recipes surfaces first.
    /// Suggestion-only staples are absent (count 0) and rank after equals.
    private let usageCounts: [String: Int]
    /// Lowercased name, cached so filtering per keystroke does no allocation
    /// beyond the result array.
    private let searchKeys: [(name: String, lowercased: String)]

    init(recipes: [Recipe]) {
        var counts: [String: Int] = [:]
        for recipe in recipes {
            for ingredient in recipe.ingredients {
                let canonical = Self.displayAliases[ingredient.name] ?? ingredient.name
                counts[canonical, default: 0] += 1
            }
        }
        usageCounts = counts

        var unique = Set(counts.keys)
        unique.formUnion(Self.suggestionOnlyStaples)
        names = unique.sorted()
        searchKeys = names.map { ($0, $0.lowercased()) }
    }

    /// Matches for what the user has typed so far: whole-string prefix matches
    /// first, then substring matches, each ranked by how many bundled recipes
    /// use the name. Typing "to" surfaces "tomato" and "tomatillo" before
    /// "canned tomato" and "cherry tomatoes".
    ///
    /// Returns nothing for a query under two characters — a one-letter query
    /// matches most of the list and is noise rather than a suggestion.
    func suggestions(for query: String, limit: Int = 8) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return [] }

        var prefixMatches: [String] = []
        var substringMatches: [String] = []
        for entry in searchKeys {
            if entry.lowercased.hasPrefix(needle) {
                prefixMatches.append(entry.name)
            } else if entry.lowercased.contains(needle) {
                substringMatches.append(entry.name)
            }
        }

        let ranked = rank(prefixMatches) + rank(substringMatches)
        return Array(ranked.prefix(limit))
    }

    /// True when the name is one the bundled recipes actually use — i.e. this
    /// ingredient will consolidate with built-in recipes in the grocery list.
    /// Suggestion-only staples are canonical for spelling but consolidate with
    /// nothing, so they report false.
    func isUsedByBundledRecipes(_ name: String) -> Bool {
        usageCounts[name] != nil
    }

    private func rank(_ matches: [String]) -> [String] {
        matches.sorted {
            let left = usageCounts[$0] ?? 0
            let right = usageCounts[$1] ?? 0
            return left == right ? $0 < $1 : left > right
        }
    }

    // MARK: Display aliases

    /// Minority spellings collapsed onto the dominant one FOR SUGGESTIONS ONLY.
    ///
    /// The bundled data really does contain both "peanut" (3 recipes) and
    /// "peanuts" (26), "olive" and "olives", "canned chickpea" and "canned
    /// chickpeas", and so on. Offering the user both spellings of one thing
    /// would be a coin flip that decides whether their ingredient consolidates
    /// with 26 recipes or 3.
    ///
    /// This is a DISPLAY ALIAS over the still-open ingredient-key
    /// fragmentation in meal-seek-recipes.json — NOT a fix for it. The recipe
    /// JSON is untouched, both spellings still exist in the data, and the
    /// grocery list still treats them as separate rows where built-in recipes
    /// use them. Collapsing the keys properly means editing the recipe data
    /// and re-running the translation pipeline; that work is not done here.
    static let displayAliases: [String: String] = [
        // Singular → dominant plural.
        "blueberry": "blueberries",
        "breadcrumb": "breadcrumbs",
        "canned black bean": "canned black beans",
        "canned cannellini bean": "canned cannellini beans",
        "canned chickpea": "canned chickpeas",
        "green bean": "green beans",
        "mustard seed": "mustard seeds",
        "olive": "olives",
        "pea": "peas",
        "peanut": "peanuts",
        "rice noodle": "rice noodles",
        "rolled oat": "rolled oats",
        "sesame seed": "sesame seeds",
        "soba noodle": "soba noodles",
        "udon noodle": "udon noodles",
        "wheat noodle": "wheat noodles",
        // Bare form → the fuller name used by more recipes.
        "ciabatta": "ciabatta bread",
        "pita": "pita bread",
        "panko": "panko breadcrumbs",
        "fusilli": "fusilli pasta",
        "flour": "all-purpose flour",
    ]

    // MARK: Suggestion-only staples

    /// Common items no bundled recipe uses. They exist so a user typing
    /// "shallot" or "baking soda" gets a canonical spelling and a correct
    /// allergen read instead of an empty dropdown. No bundled recipe
    /// references these, so they never appear in a grocery list on their own.
    ///
    /// An entry LEAVES this list the moment a bundled recipe starts using the
    /// name: from then on it arrives from source 1, with a real usage count
    /// behind it, and leaving it here would only assert something untrue.
    /// The rule is enforced by `tests/run-user-recipe-tests.sh`, which fails if
    /// any name here is used by a bundled recipe — added after nine entries had
    /// drifted into exactly that state across the side and main authoring.
    /// `cauliflower`, `asparagus` and `anchovies` left when the universal sides
    /// were authored; `shallot`, `radish`, `okra`, `parsnip`, `nutmeg`,
    /// `butternut squash`, `dark chocolate`, `dry red wine` and `white wine
    /// vinegar` left as the per-cuisine sides and the mains landed; `active dry
    /// yeast` had already been overtaken long before any of it. The V3 recipes
    /// took 22 more: `allspice`, `apple cider vinegar`, `baking soda`, `beef
    /// brisket`, `beer`, `blue cheese`, `bread flour`, `brown sugar`, `chicken
    /// wings`, `duck breast`, `fennel`, `ghee`, `ground lamb`, `horseradish`,
    /// `hot sauce`, `leek`, `molasses`, `peach`, `sake`, `shaoxing wine`, `swiss
    /// cheese` and `whole chicken`.
    static let suggestionOnlyStaples: [String] = [
        // Cooking wine & alcohol — absent entirely from the bundled data.
        "dry white wine", "dry sherry", "marsala wine", "brandy",
        // Hot sauces, vinegars, condiments.
        "sriracha", "white vinegar", "chili garlic sauce", "sambal oelek",
        "harissa", "pickle relish",
        // Baking.
        "powdered sugar", "chocolate chips", "almond flour", "raisins",
        "dried cranberries", "shredded coconut", "corn syrup",
        // Produce.
        "strawberries", "raspberries", "mango", "grapes", "snap peas",
        "swiss chard",
        // Proteins.
        "lamb shoulder", "cod fillet", "tilapia fillet", "scallops",
        "mussels", "clams",
        // Dairy & milks.
        "goat cheese", "mascarpone", "buttermilk", "half-and-half",
        "sweetened condensed milk", "oat milk", "soy milk",
        // Spices.
        "cayenne pepper", "fennel seeds", "dried sage", "tarragon",
        "italian seasoning", "za'atar", "chinese five spice",
        // Oils & fats.
        "coconut oil", "canola oil", "peanut oil",
    ]

    /// Units offered in the ingredient editor, in the order they appear in the
    /// bundled data by frequency. "to taste" items carry no unit at all, which
    /// `Ingredient.unit == nil` already models.
    static let units: [String] = [
        "g", "piece", "tbsp", "tsp", "can", "clove", "ml", "slice", "pinch", "l",
    ]
}
