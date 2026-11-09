//
//  AllergenTable.swift
//  Meal Seek
//
//  Maps a free-typed ingredient name to the allergens it implies, so a
//  user-created recipe can PRE-TICK its allergen chips instead of leaving the
//  user to remember all nine. The user always confirms; nothing here is
//  authoritative on its own.
//
//  Two rules make this safe enough to put in front of a user:
//
//  1. Matching is LONGEST-KEY-FIRST WITH SPAN CONSUMPTION, never plain
//     `contains`. Once a key claims a span of the name, no shorter key may
//     match inside it. That is what stops "almond milk" reading as dairy,
//     "eggplant" as egg, "buckwheat" as gluten, "peanut butter" as dairy,
//     "shellfish" as fish, and "rice flour" as gluten. Zero-allergen
//     "consumer" keys exist purely to claim a span and block a shorter key.
//
//  2. An unmatched ingredient contributes NOTHING. There is no inferred
//     "safe" — an empty result means "this table has no opinion", which is
//     why the confirm step is never skipped.
//
//  Deliberately NOT derived statistically from the bundled 647 recipes:
//  co-occurrence across that set yields jalapeno→dairy, capers→gluten,
//  pear→sesame and cardamom→tree_nut. Every row below is hand-authored.
//
//  Reviewed judgment calls, recorded so they aren't silently "fixed" later:
//  - oats are NOT gluten (botanically gluten-free; cross-contamination is a
//    sourcing property, not an ingredient one, and the bundled data agrees).
//  - coconut is NOT tree_nut (FDA labels it one; most tree-nut reactors
//    tolerate it, and the bundled data doesn't flag it across 39 uses).
//    Chosen knowingly — a coconut-reactive user ticks it at confirm.
//  - soba IS gluten (essentially all commercial soba is cut with wheat)
//    while bare buckwheat is not.
//  - granola, sausage/chorizo/deli meats, broths, dark chocolate and
//    barbecue sauce are left unflagged: brand-variable, and flagging the
//    majority-safe case trains users to distrust the pre-ticked chips.
//  - "soybean" is its own key even though "soy" already exists, because the
//    whole-word boundary rule cannot see a key that is glued to the front of
//    a longer word: "soy" does not match inside "soybean". Added after a
//    candidate ingredient ("soybean paste") derived nothing. No bundled
//    recipe uses a "soybean*" name today — the four soy pastes in the corpus
//    are doubanjiang, gochujang, gluten-free gochujang and miso paste, all of
//    which already matched — so this closes a latent gap rather than a live
//    bug. It also now covers soybean oil, which is a deliberate choice in the
//    over-declaring direction: refined soybean oil is tolerated by most
//    soy-allergic people, but this table warns and the user confirms.
//  - "sole" and "arctic char" are fish species the table had never met.
//    Neither appears in the bundled corpus; both were found while checking
//    proposed new recipes. "arctic char" rather than bare "char", which would
//    be a boundary-rule accident waiting to happen.
//  - Landing 1,654 new recipes added 81 keys (below, each commented). The
//    calls worth recording: plain vermicelli is wheat but rice vermicelli is
//    not (consumer key); cuttlefish is shellfish, like squid and octopus;
//    dashi is fish; spaetzle, maultaschen, pelmeni, tortellini and ravioli
//    carry egg as well as gluten. Left UNFLAGGED on purpose, as brand-variable:
//    okonomiyaki / tonkatsu / yakisoba sauce, crispy fried onions, buckwheat
//    noodles, fish cakes' wheat starch, and bare "noodle".
//  - Added after the landing, on a final read of every name that derived
//    nothing: "mole sauce" (peanut, tree_nut, sesame), "kvass" (gluten) and
//    "yellow curry paste" (fish, like its red and green siblings). Left alone:
//    gofio (wheat or maize by island), granola, and the brand-variable list above.
//

import Foundation

enum AllergenTable {
    /// The nine allergens tracked app-wide, matching the strings used in
    /// `Recipe.allergens` and `UserPreferences.allergens`.
    static let dairy = "dairy"
    static let egg = "egg"
    static let fish = "fish"
    static let shellfish = "shellfish"
    static let gluten = "gluten"
    static let soy = "soy"
    static let peanut = "peanut"
    static let treeNut = "tree_nut"
    static let sesame = "sesame"

    /// All nine, in the order the Allergies settings screen lists them, so
    /// the Add Recipe chips read in the same order the user already knows.
    static let allTracked = [
        gluten, dairy, egg, soy, peanut, treeNut, shellfish, fish, sesame,
    ]

    /// Every key, with the allergens it implies. An empty array is a
    /// "consumer": it claims its span so a shorter key can't match inside it,
    /// while contributing no allergen of its own.
    ///
    /// Order here is for human review only — matching always sorts by key
    /// length, longest first.
    static let entries: [String: [String]] = [
        // MARK: Dairy
        "milk": [dairy],
        "buttermilk": [dairy],
        "butter": [dairy],
        "ghee": [dairy],
        "cream": [dairy],
        "yogurt": [dairy],
        "cheese": [dairy],
        "cheddar": [dairy],
        "parmesan": [dairy],
        "parmigiano": [dairy],
        "mozzarella": [dairy],
        "ricotta": [dairy],
        "mascarpone": [dairy],
        "feta": [dairy],
        "gruyere": [dairy],
        "paneer": [dairy],
        "halloumi": [dairy],
        "cotija": [dairy],
        "queso": [dairy],
        "provolone": [dairy],
        "gouda": [dairy],
        "monterey jack": [dairy],
        "brie": [dairy],
        "pecorino": [dairy],
        "gorgonzola": [dairy],
        "swiss": [dairy],
        "whey": [dairy],
        "casein": [dairy],
        "half-and-half": [dairy],
        "half and half": [dairy],
        "buffalo sauce": [dairy],
        "custard": [dairy, egg],
        "pesto": [dairy, treeNut],
        "ranch": [dairy, egg],
        "chocolate chips": [dairy, soy],
        // Fermented / cultured dairy and a Brazilian grilling cheese, all
        // found while landing the V3 candidates. "crema" is the Mexican table
        // cream, which "cream" cannot match because the whole-word rule needs a
        // non-letter after the key.
        "kefir": [dairy],
        "labneh": [dairy],
        "crema": [dairy],
        "queijo coalho": [dairy],

        // MARK: Egg
        "egg": [egg],
        "mayonnaise": [egg],
        "mayo": [egg],
        "aioli": [egg],
        "meringue": [egg],

        // MARK: Fish
        "fish": [fish],
        "fish sauce": [fish],
        "salmon": [fish],
        "tuna": [fish],
        "cod": [fish],
        "tilapia": [fish],
        "anchovy": [fish],
        "anchovies": [fish],
        "sardine": [fish],
        "halibut": [fish],
        "trout": [fish],
        "mackerel": [fish],
        "bonito": [fish],
        "sole": [fish],
        "arctic char": [fish],
        "sea bass": [fish],
        // Species met while landing the V3 candidates. Whole words only, so
        // "carp" cannot match inside "carpaccio" nor "eel" inside "steel".
        "eel": [fish],
        "unagi": [fish],
        "hake": [fish],
        "plaice": [fish],
        "sea bream": [fish],
        "bream": [fish],
        "pickerel": [fish],
        "pike": [fish],
        "perch": [fish],
        "pirarucu": [fish],
        "sturgeon": [fish],
        "carp": [fish],
        "catfish": [fish],
        "herring": [fish],
        "yellowtail": [fish],
        "haddock": [fish],
        "pollock": [fish],
        "snapper": [fish],
        "grouper": [fish],
        "swordfish": [fish],
        "turbot": [fish],
        "monkfish": [fish],
        "smelt": [fish],
        "caviar": [fish],
        "roe": [fish],
        "surimi": [fish],
        // Dashi is bonito-based; kombu-only dashi exists but is the rarer case
        // and this table warns while the user confirms.
        "dashi": [fish],
        // Contains anchovy — routinely missed when reading a label.
        "worcestershire": [fish],
        // Fish sauce and/or shrimp paste. `vegan kimchi` below is the exception.
        "kimchi": [fish],
        "red curry paste": [fish],
        "green curry paste": [fish],
        "yellow curry paste": [fish],

        // MARK: Shellfish
        // Claims the span so "fish" can't also match inside "shellfish".
        "shellfish": [shellfish],
        "shrimp": [shellfish],
        "prawn": [shellfish],
        "crab": [shellfish],
        "lobster": [shellfish],
        "scallop": [shellfish],
        "mussel": [shellfish],
        "clam": [shellfish],
        "squid": [shellfish],
        "calamari": [shellfish],
        "octopus": [shellfish],
        "crawfish": [shellfish],
        "oyster": [shellfish],
        "oyster sauce": [shellfish, gluten],
        // Molluscs and crustaceans the table had not met. Cuttlefish follows the
        // same call as squid and octopus above: filed under shellfish.
        "cuttlefish": [shellfish],
        "crayfish": [shellfish],
        "langoustine": [shellfish],
        "abalone": [shellfish],
        "cockle": [shellfish],
        "conch": [shellfish],
        "sea urchin": [shellfish],

        // MARK: Gluten
        "wheat": [gluten],
        "flour": [gluten],
        "bread": [gluten],
        "breadcrumb": [gluten],
        "panko": [gluten],
        "pasta": [gluten],
        "spaghetti": [gluten],
        "penne": [gluten],
        "fusilli": [gluten],
        "orzo": [gluten],
        "macaroni": [gluten],
        "lasagna": [gluten],
        "ziti": [gluten],
        "pappardelle": [gluten],
        "gnocchi": [gluten],
        "couscous": [gluten],
        "semolina": [gluten],
        "farro": [gluten],
        "bulgur": [gluten],
        "barley": [gluten],
        "rye": [gluten],
        "seitan": [gluten],
        "malt": [gluten],
        "beer": [gluten],
        // Bread kvass — fermented from rye bread or malt. Beet kvass exists and
        // is the rare case; this table warns while the user confirms.
        "kvass": [gluten],
        "ciabatta": [gluten],
        "pita": [gluten],
        "muffin": [gluten],
        "sub roll": [gluten],
        "pastry": [gluten],
        "curry roux": [gluten],
        "flour tortilla": [gluten],
        "udon": [gluten],
        "ramen": [gluten],
        "chow mein": [gluten],
        "wheat noodles": [gluten],
        // Commercial soba is cut with wheat; bare buckwheat is not (consumer below).
        "soba": [gluten],
        // Wheat-fermented, unlike sake or wine.
        "shaoxing wine": [gluten],
        "egg noodles": [gluten, egg],
        "wonton wrapper": [gluten, egg],
        // Wheat products met while landing the V3 candidates. Each was either
        // declared only by hand or not at all, which is the audit's blind spot:
        // it can only compare declarations against keys the table has.
        "phyllo": [gluten],
        "filo": [gluten],
        "vermicelli": [gluten],
        "somen": [gluten],
        "mandu": [gluten],
        "gyoza": [gluten],
        "pelmeni": [gluten, egg],
        "spaetzle": [gluten, egg],
        "maultaschen": [gluten, egg],
        "schupfnudeln": [gluten],
        "kaiser roll": [gluten],
        "hoagie roll": [gluten],
        "hot dog bun": [gluten],
        "bread roll": [gluten],
        "bolillo": [gluten],
        "cornbread": [gluten],
        "flatbread": [gluten],
        "roti": [gluten],
        "bannock": [gluten],
        "hardtack": [gluten],
        "gingerbread": [gluten],
        "cracker": [gluten],
        "sourdough": [gluten],
        "freekeh": [gluten],
        "msemen": [gluten],
        "ramyeon noodle": [gluten],
        "ramyun noodle": [gluten],
        "spring roll wrapper": [gluten],
        "fried wonton crisp": [gluten, egg],
        // Pasta shapes: "pasta" only matches when the word itself is present.
        "bucatini": [gluten],
        "rigatoni": [gluten],
        "tagliatelle": [gluten],
        "orecchiette": [gluten],
        "linguine": [gluten],
        "fettuccine": [gluten],
        "tortellini": [gluten, egg],
        "ravioli": [gluten, egg],
        "cannelloni": [gluten],

        // MARK: Soy
        "soy": [soy],
        // "soy" cannot match inside "soybean" — the boundary rule requires a
        // non-letter after the key, and "soybean" has none. This is the key
        // that catches soybean paste, soybean oil and soybean sprouts.
        "soybean": [soy],
        "tofu": [soy],
        "edamame": [soy],
        // Douchi — fermented, salted black SOYBEANS, not the unrelated black
        // turtle bean. Full phrase so a plain "black beans" (legume, no soy)
        // elsewhere in the corpus is never caught by this.
        "fermented black beans": [soy],
        "miso": [soy],
        "tempeh": [soy],
        "natto": [soy],
        "tamari": [soy],
        "ponzu": [soy],
        "soy milk": [soy],
        // Wheat-brewed, unlike tamari — the whole reason both are in the data.
        "soy sauce": [soy, gluten],
        "gochujang": [soy, gluten],
        "doubanjiang": [soy, gluten],
        "hoisin": [soy, gluten],
        // Commercial doenjang is routinely wheat-cut, same call as gochujang;
        // traditional 재래식 doenjang is soy-only but brand variance is the
        // majority case, same reasoning as soy sauce vs tamari above.
        "doenjang": [soy, gluten],
        // Fermented soybean pastes met while landing the V3 candidates.
        "douchi": [soy],
        "fermented red bean curd": [soy],
        "black bean paste": [soy, gluten],
        "ssamjang": [soy, gluten],

        // MARK: Peanut
        "peanut": [peanut],
        "groundnut": [peanut],
        "satay": [peanut],
        "peanut butter": [peanut],
        "massaman curry paste": [peanut, fish],
        "panang curry paste": [peanut, fish],

        // MARK: Tree nut
        "almond": [treeNut],
        "cashew": [treeNut],
        "walnut": [treeNut],
        "pecan": [treeNut],
        "pistachio": [treeNut],
        "hazelnut": [treeNut],
        "macadamia": [treeNut],
        "brazil nut": [treeNut],
        "pine nut": [treeNut],
        "chestnut": [treeNut],
        "praline": [treeNut],
        "marzipan": [treeNut],
        "nutella": [treeNut],
        // Span the whole phrase so "milk"/"butter"/"flour" can't also match.
        "almond milk": [treeNut],
        "cashew milk": [treeNut],
        "almond butter": [treeNut],
        "cashew butter": [treeNut],
        "almond flour": [treeNut],

        // MARK: Sesame
        "sesame": [sesame],
        "tahini": [sesame],
        // Prepared mole (poblano, negro): peanuts or almonds, and sesame, in
        // essentially every version. Home-made moles list their own nuts.
        "mole sauce": [peanut, treeNut, sesame],
        "halva": [sesame],
        "za'atar": [sesame],
        "zaatar": [sesame],
        // Tahini-based — commonly missed.
        "hummus": [sesame],

        // MARK: Consumers — no allergen; they exist only to claim a span and
        // block a shorter key from matching inside it.
        "eggplant": [],           // egg
        "butternut squash": [],   // butter
        "butter lettuce": [],     // butter
        "apple butter": [],       // butter
        "cocoa butter": [],       // butter
        "cream of tartar": [],    // cream
        "swiss chard": [],        // swiss
        "buckwheat": [],          // wheat
        "water chestnut": [],     // chestnut
        "vegan kimchi": [],       // kimchi
        "corn tortilla": [],      // pairs with flour tortilla
        "coconut": [],            // see the coconut note in the file header
        "coconut milk": [],       // milk
        "coconut cream": [],      // cream
        "coconut oil": [],        // coconut
        "coconut flour": [],      // flour
        "oat milk": [],           // milk
        "rice milk": [],          // milk
        "rice flour": [],         // flour
        "corn flour": [],         // flour
        "chickpea flour": [],     // flour
        "cassava flour": [],      // flour
        "tapioca flour": [],      // flour
        "buckwheat flour": [],    // flour
        "oat flour": [],          // flour
        "rice vermicelli": [],    // vermicelli
    ]

    /// Phrases that REMOVE an allergen the keys would otherwise add, for
    /// substitute products named after the thing they replace ("oat milk" is
    /// handled as a consumer; "dairy-free cheese" needs this).
    private static let suppressors: [(phrase: String, allergens: [String])] = [
        ("dairy-free", [dairy]),
        ("dairy free", [dairy]),
        ("non-dairy", [dairy]),
        ("lactose-free", [dairy]),
        ("gluten-free", [gluten]),
        ("gluten free", [gluten]),
        ("egg-free", [egg]),
        ("egg free", [egg]),
        ("nut-free", [treeNut, peanut]),
        ("nut free", [treeNut, peanut]),
        ("vegan", [dairy, egg]),
    ]

    /// Keys sorted longest-first, computed once. Length order is what makes
    /// span consumption correct: a longer, more specific key always gets to
    /// claim its span before a shorter one can match inside it.
    private static let keysByLengthDescending: [String] = entries.keys
        .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }

    /// The allergens implied by one free-typed ingredient name. Empty means
    /// the table has no opinion — never "safe".
    static func allergens(forIngredientNamed name: String) -> Set<String> {
        let normalized = name.lowercased()
        guard !normalized.isEmpty else { return [] }
        let characters = Array(normalized)

        var claimed: [Range<Int>] = []
        var found: Set<String> = []

        for key in keysByLengthDescending {
            let keyCharacters = Array(key)
            for range in ranges(of: keyCharacters, in: characters) {
                guard !claimed.contains(where: { $0.overlaps(range) }) else { continue }
                claimed.append(range)
                found.formUnion(entries[key] ?? [])
            }
        }

        for suppressor in suppressors where normalized.contains(suppressor.phrase) {
            found.subtract(suppressor.allergens)
        }
        return found
    }

    /// The union across a recipe's ingredients — what pre-ticks the allergen
    /// chips on the Add Recipe screen.
    static func allergens(for ingredients: [Ingredient]) -> Set<String> {
        ingredients.reduce(into: Set<String>()) { result, ingredient in
            result.formUnion(allergens(forIngredientNamed: ingredient.name))
        }
    }

    /// Every whole-word occurrence of `key` in `text`, tolerating a trailing
    /// "s"/"es" so one key covers its own plural. A match must start and end
    /// on a word boundary, which is what keeps "egg" out of "eggplant" and
    /// "wheat" out of "buckwheat" before span consumption even applies.
    private static func ranges(of key: [Character], in text: [Character]) -> [Range<Int>] {
        guard !key.isEmpty, key.count <= text.count else { return [] }
        var results: [Range<Int>] = []

        for start in 0...(text.count - key.count) {
            guard isBoundary(text, before: start) else { continue }
            guard Array(text[start..<(start + key.count)]) == key else { continue }

            // Accept the bare key, or the key plus a plural suffix, whichever
            // lands on a word boundary.
            for suffixLength in [0, 1, 2] {
                let end = start + key.count + suffixLength
                guard end <= text.count else { break }
                let suffix = String(text[(start + key.count)..<end])
                guard suffix.isEmpty || suffix == "s" || suffix == "es" else { continue }
                if isBoundary(text, at: end) {
                    results.append(start..<end)
                    break
                }
            }
        }
        return results
    }

    private static func isBoundary(_ text: [Character], before index: Int) -> Bool {
        index == 0 || !text[index - 1].isLetter && !text[index - 1].isNumber
    }

    private static func isBoundary(_ text: [Character], at index: Int) -> Bool {
        index == text.count || !text[index].isLetter && !text[index].isNumber
    }
}
