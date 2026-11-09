//
//  ShoppingListBuilder.swift
//  Meal Seek
//
//  The SHOPPING layer over canonical grocery consolidation. Recipe instructions
//  speak in cooking units (2 cloves garlic, 1 tbsp butter); a shopping list must
//  speak in what people actually buy. This is a pure post-pass that runs AFTER
//  `GroceryListBuilder.aggregate` has summed the week in canonical base units —
//  it never re-touches summation, so it cannot reintroduce the unit-bucket
//  splitting that once caused a silent undercount.
//
//  What it does, per canonical ingredient:
//    • pantry staples (salt, oils, dried spices, …) → one row, NO quantity,
//      flagged for the "Check your pantry" section;
//    • family-crossing conversions to grams (garlic clove→g, butter tbsp→g,
//      ginger tbsp/tsp→g, bacon/bread slice→g) via a per-ingredient density;
//    • liquid condiments displayed in ml (tbsp/tsp→ml, exact, no density);
//    • everything else unchanged from `GroceryListBuilder.build`;
//    • MERGE: rows that land in the same shopping unit after conversion (e.g.
//      ginger's native-gram row and its converted volume row) collapse into ONE
//      row whose amount is the SUM of the true required amounts;
//    • round UP to a purchasable amount — never down, so the week is never
//      under-bought.
//
//  DISPLAY-ONLY: like ingredient names, shopping units are canonical English
//  here (g/kg/ml/l are international symbols, so they render unchanged in every
//  language); the pantry section header is the only new UI string and flows
//  through the String Catalog. Nothing here reaches generation, allergen
//  filtering, or the recipe card.
//

import Foundation

enum ShoppingListBuilder {
    // MARK: Shopping table

    /// Ingredients whose recipe unit crosses families into MASS. The value is the
    /// per-ingredient density: grams produced per ONE source base unit — grams
    /// per ml for a volume source (butter, ginger), grams per single count for a
    /// count source (garlic per clove; bacon/bread per slice). A native-gram row
    /// of the same ingredient (ginger sometimes ships in grams) needs no density
    /// and is summed straight in. Reviewed factors, tunable in one place.
    static let gramsPerSourceBase: [String: Double] = [
        // count → g (grams per single unit)
        "garlic": 5.0,                 // 5 g per clove (medium clove ≈ 4–6 g)
        "bacon": 20.0,                 // 20 g per slice (one raw strip)
        "bread": 30.0,                 // 30 g per slice (sandwich loaf)
        "sandwich bread": 30.0,        // 30 g per slice
        "rye bread": 32.0,             // 32 g per slice (denser)
        "brioche bread": 35.0,         // 35 g per slice (enriched)
        "sourdough bread": 40.0,       // 40 g per slice (artisan)
        "ciabatta": 40.0,              // 40 g per slice
        "ciabatta bread": 40.0,        // 40 g per slice
        "crusty bread": 40.0,          // 40 g per slice
        // volume → g (grams per ml)
        "butter": 14.2 / 15.0,         // 14.2 g per tbsp
        "ginger": 0.4,                 // 6 g per tbsp = 2 g per tsp
        // Spoon-measured solids. Nobody buys "3 tbsp of flour", so these cross
        // into grams like butter does. Flour also stops splitting into a
        // mass row plus a volume row: the density routes both into one gram
        // bucket, which is the merge doing its job.
        "all-purpose flour": 7.5 / 15.0,     // 7.5 g per tbsp (spooned, not packed)
        "capers": 9.0 / 15.0,                // 9 g per tbsp (drained)
        "chia seeds": 12.0 / 15.0,           // 12 g per tbsp
        "chipotle in adobo": 15.0 / 15.0,    // 15 g per tbsp (pepper + sauce)
        "toasted rice powder": 8.0 / 15.0,   // 8 g per tbsp
        // Landing the V3 recipes surfaced this one: ghee is sold by the jar in
        // grams and weighs a touch less than butter. (Plain "flour" is not here:
        // the landing unified it to "all-purpose flour", which has its entry above.)
        "ghee": 13.0 / 15.0,                 // 13 g per tbsp
    ]

    /// Produce you buy as whole items, with the grams ONE item weighs.
    ///
    /// A recipe measuring 30 g of cucumber is describing a slice of one; the
    /// shop sells the cucumber. Without this, a name used in both `piece` and
    /// `g` splits into two rows and the gram row shows the leftover crumbs —
    /// the 0.5 g cucumber that prompted this. Converting mass into pieces
    /// merges both back into one row that rounds UP to a whole item.
    ///
    /// Only whole-unit produce belongs here. Anything genuinely sold by weight
    /// — spinach, mushrooms, berries, green beans, cherry tomatoes, shredded
    /// coconut, ground meat, grated cheese — must stay in grams.
    static let gramsPerWholeItem: [String: Double] = [
        "cucumber": 300,
        "tomato": 120,
        "orange": 130,
        "lettuce": 300,
        "romaine lettuce": 300,
        "potato": 170,
        "sweet potato": 200,
        "cabbage": 900,
        "red cabbage": 900,
        "broccoli": 350,          // one head
        "pineapple": 900,
        "green papaya": 1000,
        "bok choy": 150,          // one head
        "chinese broccoli": 200,  // one bunch-sized head
    ]

    /// Soft herbs, with the grams ONE supermarket bunch weighs. Sold by the
    /// bunch or packet everywhere; "4 g parsley" is as unbuyable as a 0.5 g
    /// cucumber. `bunch` is a countable unit (see
    /// `GroceryListBuilder.countableUnits`) so it rounds up to whole bunches —
    /// there is no such thing as half a bunch on a shopping list.
    static let gramsPerBunch: [String: Double] = [
        "cilantro": 25,
        "parsley": 25,
        "basil": 25,
        "chives": 20,
        "mint": 25,
        "dill": 20,
        "thai basil": 25,
    ]

    /// What ONE can of each canned ingredient weighs, in grams. The can stays
    /// the unit you buy in — but can sizes differ by shop and country, so the
    /// list also shows the total weight ("2 can (~800 g)"). A shopper holding
    /// 250 g tins can then work out they need three, instead of guessing what
    /// size "2 cans" assumed.
    ///
    /// 400 g is the standard European/UK tin. Singular and plural spellings are
    /// both listed because the canonical data genuinely contains both — that is
    /// the known ingredient-key fragmentation, deliberately not fixed here.
    static let gramsPerCan: [String: Double] = [
        "canned black bean": 400, "canned black beans": 400,
        "canned cannellini bean": 400, "canned cannellini beans": 400,
        "canned chickpea": 400, "canned chickpeas": 400,
        "canned kidney beans": 400,
        "canned pinto bean": 400,
        "canned refried beans": 400,
        "canned crushed tomatoes": 400,
        "canned diced tomatoes": 400,
        "canned tomato": 400,
        "canned hominy": 400,
        "canned peas": 400,
        "canned coconut milk": 400,     // 400 ml tin ≈ 400 g
        "canned bamboo shoot": 225,     // 8 oz drained tin
        "canned tuna": 145,             // standard small tin
    ]

    /// Liquid condiments shown in millilitres. tbsp/tsp/ml are all the volume
    /// family, so this is an exact display choice (×15 / ×5), no density: it just
    /// pins the display unit to ml/l instead of the contributing-units default,
    /// so "8 tbsp soy sauce" reads as "120 ml soy sauce".
    static let displayInMilliliters: Set<String> = [
        "soy sauce", "dark soy sauce", "tamari", "fish sauce", "oyster sauce",
        "hoisin sauce",
        "worcestershire sauce", "mirin", "shaoxing wine", "rice vinegar", "red wine vinegar",
        "balsamic vinegar", "white wine vinegar", "vinegar", "ketchup",
        "mayonnaise", "dijon mustard",
        "mustard", "whole grain mustard", "barbecue sauce", "buffalo sauce",
        "ranch dressing", "salsa", "maple syrup", "honey",
    ]

    /// Pantry staples — things nobody buys per-recipe. They appear in the grocery
    /// list WITHOUT a computed quantity, grouped under "Check your pantry", so a
    /// summed "14 tbsp olive oil" never appears while the shopper is still told
    /// the week needs it. Sesame oil is BOTH a staple and a sesame allergen; that
    /// is fine — allergen filtering reads `Recipe`, not this list.
    static let pantryStaples: Set<String> = [
        // salt & pepper
        "salt", "black pepper", "white pepper",
        // cooking oils
        "olive oil", "vegetable oil", "sesame oil", "chili oil", "sunflower oil",
        // sweeteners (granulated, and rock sugar's crystals — both bought by the bag)
        "sugar", "coconut sugar", "rock sugar",
        // baking / thickener
        "cornstarch", "baking powder", "vanilla extract", "cocoa powder",
        // dried spices & herbs
        "cumin", "paprika", "smoked paprika", "oregano", "chili powder",
        "turmeric", "cinnamon", "coriander", "garam masala", "curry powder",
        "cardamom", "cloves", "bay leaf", "nutmeg", "chili flakes",
        "red pepper flakes",
        "garlic powder", "mustard seed", "mustard seeds", "caraway seeds",
        "thyme", "rosemary", "saffron", "gochugaru", "chaat masala",
        "herbs de provence", "sichuan peppercorn", "star anise", "dried chili",
        "dried chili pepper", "sesame seed", "sesame seeds",
        // jarred pastes & nut butters — bought by the jar in whatever size a store
        // carries, used by the spoonful; a summed "6 tbsp gochujang" is noise. Thin
        // pourable condiments (soy/fish sauce, vinegars, syrups) stay in ml above —
        // only thick jarred pastes belong here. Some are also allergens (peanut
        // butter → peanut, tahini → sesame, miso/doubanjiang → soy); that is fine,
        // allergen filtering reads `Recipe`, not this list — exactly like sesame oil.
        "miso paste", "doenjang", "doubanjiang", "gochujang", "gluten-free gochujang", "tahini", "peanut butter",
        "fermented black beans",
        "tomato paste", "tamarind paste", "aji amarillo paste",
        "red curry paste", "green curry paste", "panang curry paste",
        "massaman curry paste",
        // other pantry
        "nutritional yeast",
        // Landing the V3 recipes brought ~30 spoon-measured names that matched no
        // density, no ml pin and no staple entry, so they reached the list as
        // "9 tsp coriander powder" — the exact failure the FIX 1 sweep in the
        // grocery tests exists to catch. They are staples for the same reason
        // cumin and gochujang are: used by the spoonful, bought by the jar, and
        // a summed teaspoon count is noise. Relabelling them "ml" in the data was
        // tried and rejected — it moves the problem (15 ml of wheat flour) and
        // passes the sweep without making anything buyable.
        //   dried spices and salts
        "allspice", "baking soda", "cayenne", "fennel powder", "fennel seed",
        "fenugreek", "five spice", "green peppercorn", "kashmiri chili",
        "ras el hanout", "sambar powder", "seven spice", "sumac", "zaatar",
        //   sweeteners, sold by the bag like sugar above
        "brown sugar", "palm sugar",
        //   jarred pastes and pickled seasonings
        "achiote paste", "black bean paste", "douchi", "shrimp paste", "soybean paste", "sweet bean paste", "thai chili jam",
        "wasabi", "yellow curry paste",
    ]

    // MARK: Build

    /// The week's shopping list. Consumes `GroceryListBuilder.aggregate` (the
    /// UNROUNDED canonical totals) and applies the shopping table on top. Row ids
    /// stay `name`, or `name#family` when an ingredient still legitimately splits
    /// across shopping units (e.g. potato bought both by piece and by weight), so
    /// existing bought-state and the `name#family` contract survive unchanged.
    /// Whether an ingredient is treated as a pantry staple for THIS user: their
    /// explicit decision if they made one, otherwise the shipped default.
    ///
    /// This is the single place the two sources combine, so there is one answer
    /// to "is this a staple" everywhere — the list, the settings screen, and the
    /// tests. It decides only whether a QUANTITY is computed; it has no bearing
    /// on allergens, which are read from `Recipe` by `RecipeFilter`.
    static func isPantryStaple(_ name: String, overrides: [String: Bool]) -> Bool {
        overrides[name] ?? pantryStaples.contains(name)
    }

    /// Ingredients the user has explicitly decided about, i.e. where their
    /// choice differs from the shipped default. This is what the settings
    /// screen shows as "marked by you" and what its reset clears — a user must
    /// be able to see what they changed and undo it.
    static func userChangedNames(_ overrides: [String: Bool]) -> [String] {
        overrides
            .filter { name, isStaple in isStaple != pantryStaples.contains(name) }
            .keys
            .sorted()
    }

    static func build(
        plan: WeekPlan,
        recipes: [Recipe],
        householdSize: Int,
        pantryOverrides: [String: Bool] = [:]
    ) -> [GroceryItem] {
        build(
            aggregates: GroceryListBuilder.aggregate(plan: plan, recipes: recipes, householdSize: householdSize),
            pantryOverrides: pantryOverrides
        )
    }

    /// The shopping list for an explicit list of picked recipes.
    static func build(
        recipeIDs: [String],
        recipes: [Recipe],
        servings: Int,
        pantryOverrides: [String: Bool] = [:]
    ) -> [GroceryItem] {
        build(
            aggregates: GroceryListBuilder.aggregate(recipeIDs: recipeIDs, recipes: recipes, householdSize: servings),
            pantryOverrides: pantryOverrides
        )
    }

    private static func build(
        aggregates: [String: GroceryListBuilder.Aggregate],
        pantryOverrides: [String: Bool]
    ) -> [GroceryItem] {
        var items: [GroceryItem] = []
        for (name, aggregate) in aggregates {
            if isPantryStaple(name, overrides: pantryOverrides) {
                // One presence-only row, quantity suppressed, whatever units the
                // recipes used. Keeps its canonical category for reference.
                items.append(GroceryItem(
                    id: name, name: name, quantity: nil, unit: nil,
                    category: aggregate.category, recipeCount: aggregate.mealCount,
                    isPantryStaple: true
                ))
                continue
            }

            // Route each canonical family into a shopping bucket keyed by the
            // TARGET family's token. Family-crossing conversions collapse into a
            // shared bucket here — that collapse IS the merge; because we sum
            // unrounded base amounts before any rounding, the merged amount can
            // never be less than the sum of the true required amounts.
            var buckets: [String: GroceryListBuilder.FamilyTotal] = [:]
            for (family, total) in aggregate.families where total.baseTotal > 0 {
                let (token, target) = shoppingBucket(for: family, total: total, name: name)
                var merged = buckets[token] ?? GroceryListBuilder.FamilyTotal()
                merged.baseTotal += target.baseTotal
                merged.sourceUnits.formUnion(target.sourceUnits)
                buckets[token] = merged
            }

            if buckets.isEmpty {
                // Non-staple with no quantified family (a to-taste ingredient that
                // isn't on the staple list): one bare row, exactly as before.
                items.append(GroceryItem(
                    id: name, name: name, quantity: nil, unit: nil,
                    category: aggregate.category, recipeCount: aggregate.mealCount
                ))
                continue
            }

            let isSplit = buckets.count > 1
            for (token, total) in buckets {
                let (value, unit) = displayValue(forToken: token, total: total)
                let rounded = roundedUp(value, unit: unit)
                // Weight of the cans actually being bought — computed from the
                // ROUNDED count, not the raw total, so it describes what ends
                // up in the basket rather than an amount nobody can purchase.
                let grams = unit == "can" ? gramsPerCan[name].map { $0 * rounded } : nil
                items.append(GroceryItem(
                    id: isSplit ? "\(name)#\(token)" : name,
                    name: name,
                    quantity: rounded,
                    unit: unit,
                    category: aggregate.category,
                    recipeCount: aggregate.mealCount,
                    approximateGrams: grams
                ))
            }
        }

        items.sort {
            let left = GroceryListBuilder.aisleRank($0.category)
            let right = GroceryListBuilder.aisleRank($1.category)
            if left != right { return left < right }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
        return items
    }

    // MARK: Bucket routing

    /// Maps a canonical family-total onto its shopping bucket: a token that keys
    /// the merge, plus the amount expressed in that bucket's base unit (grams for
    /// a mass target, ml for a volume target, the count itself otherwise). The
    /// token deliberately reuses the canonical family idSuffix ("mass"/"volume"/
    /// the count unit) so identity ingredients keep their exact existing ids.
    private static func shoppingBucket(
        for family: GroceryListBuilder.UnitFamily,
        total: GroceryListBuilder.FamilyTotal,
        name: String
    ) -> (token: String, total: GroceryListBuilder.FamilyTotal) {
        // Whole-item produce and bunched herbs: convert MASS into the countable
        // unit the shop actually sells, and let an existing count family fall
        // into the same bucket so the two merge into one row instead of
        // splitting into "2 potatoes" plus "150 g of potato".
        if let perItem = gramsPerWholeItem[name] {
            return countBucket("piece", family: family, total: total, gramsPerUnit: perItem)
        }
        if let perBunch = gramsPerBunch[name] {
            return countBucket("bunch", family: family, total: total, gramsPerUnit: perBunch)
        }
        // Family-crossing conversion into grams.
        if let density = gramsPerSourceBase[name] {
            let grams: Double
            switch family {
            case .mass:            grams = total.baseTotal          // already grams
            case .volume, .count, .other: grams = total.baseTotal * density
            }
            return ("mass", GroceryListBuilder.FamilyTotal(baseTotal: grams, sourceUnits: ["g"]))
        }
        // Liquid condiment pinned to ml display (still the volume family).
        if displayInMilliliters.contains(name), case .volume = family {
            return ("volume", GroceryListBuilder.FamilyTotal(baseTotal: total.baseTotal, sourceUnits: ["ml"]))
        }
        // Identity: unchanged family, unchanged base, original contributing units.
        return (family.idSuffix, total)
    }

    /// Routes one canonical family into a countable shopping unit (`piece`,
    /// `bunch`). A mass total is divided by what one unit weighs; a total
    /// already counted in that unit passes straight through, so both land in
    /// the same bucket and merge. Volume totals for these ingredients don't
    /// occur in the data; if one ever appears it falls back to its own family
    /// rather than being silently mis-converted through a weight it has no
    /// density for.
    private static func countBucket(
        _ unit: String,
        family: GroceryListBuilder.UnitFamily,
        total: GroceryListBuilder.FamilyTotal,
        gramsPerUnit: Double
    ) -> (token: String, total: GroceryListBuilder.FamilyTotal) {
        switch family {
        case .mass:
            let count = gramsPerUnit > 0 ? total.baseTotal / gramsPerUnit : total.baseTotal
            return (unit, GroceryListBuilder.FamilyTotal(baseTotal: count, sourceUnits: [unit]))
        case .count(let existing) where existing == unit:
            return (unit, GroceryListBuilder.FamilyTotal(baseTotal: total.baseTotal, sourceUnits: [unit]))
        case .count, .volume, .other:
            return (family.idSuffix, total)
        }
    }

    /// Display value + unit for a shopping bucket. Reuses the canonical
    /// `GroceryListBuilder.displayValue` for every family so unit SELECTION is
    /// byte-identical to today (mass upgrades g→kg, volume follows contributing
    /// units, counts stay bare). Only the rounding differs — see `roundedUp`.
    private static func displayValue(
        forToken token: String, total: GroceryListBuilder.FamilyTotal
    ) -> (value: Double, unit: String) {
        switch token {
        case "mass":   return GroceryListBuilder.displayValue(for: .mass, total: total)
        case "volume": return GroceryListBuilder.displayValue(for: .volume, total: total)
        default:       return GroceryListBuilder.displayValue(for: .count(token), total: total)
        }
    }

    /// Rounds a summed shopping amount UP to a purchasable quantity — the mirror
    /// of `GroceryListBuilder.rounded` but never rounding down, so a converted
    /// quantity is never less than the true required amount (1.4 → 2 whole units;
    /// 51 g → 55 g; 12.1 g → 13 g). Countable units go up to a whole unit; weight/
    /// volume go up to the nearest 5 at ≥ 50, whole at ≥ 10, one decimal below.
    static func roundedUp(_ value: Double, unit: String?) -> Double {
        if let unit, GroceryListBuilder.countableUnits.contains(unit) {
            return value.rounded(.up)
        }
        if value >= 50 { return (value / 5).rounded(.up) * 5 }
        if value >= 10 { return value.rounded(.up) }
        return (value * 10).rounded(.up) / 10
    }
}
