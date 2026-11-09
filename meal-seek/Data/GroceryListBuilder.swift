//
//  GroceryListBuilder.swift
//  Meal Seek
//
//  Pure local derivation of a shopping list from a week's plan: aggregate by
//  canonical name with unit conversion inside compatible families (mass,
//  volume, per-unit counts), scale to household size, round to buyable
//  amounts, group by aisle. Quantities in incompatible families are never
//  converted into each other (no volume↔mass — that needs density); such an
//  ingredient becomes one correct row per family instead of one wrong number.
//  The `preparation` field is ignored — it's for cooking, not shopping.
//

import Foundation

enum GroceryListBuilder {
    /// Ingredients that never belong on a shopping list.
    static let neverShop: Set<String> = ["water"]

    /// Aisles in shopping-friendly walk order. Unknown categories sort as "other".
    static let aisleOrder = [
        "produce", "meat_seafood", "dairy_eggs", "bakery", "frozen",
        "pantry", "spices_seasonings", "condiments", "beverages", "other",
    ]

    /// Units you buy in whole numbers — you cannot buy 0.75 of an egg.
    /// Counts never convert into each other: a clove is not a slice.
    ///
    /// "bunch" is a SHOPPING-only unit: no canonical recipe uses it (the data's
    /// whole vocabulary is g/kg/ml/l/tsp/tbsp/piece/clove/can/slice/pinch), and
    /// it exists so `ShoppingListBuilder` can express soft herbs the way shops
    /// sell them. Listing it here is what makes round-up treat it as whole, so
    /// a list never asks for half a bunch.
    static let countableUnits: Set<String> = ["piece", "clove", "can", "slice", "bunch"]

    /// Grams per mass unit. Only "g" occurs in the data; "kg" exists for
    /// display upgrades (1200 g shows as 1.2 kg).
    static let massUnits: [String: Double] = ["g": 1, "kg": 1000]

    /// Milliliters per volume unit — the complete volume vocabulary of the
    /// recipe database (no cup/fl-oz/aliases exist in the data).
    static let volumeUnits: [String: Double] = ["ml": 1, "tsp": 5, "tbsp": 15, "l": 1000]

    /// A compatible-conversion bucket. Same family ⇒ quantities sum after
    /// conversion; different families ⇒ separate rows, never one number.
    enum UnitFamily: Hashable {
        case mass
        case volume
        /// One case per countable unit — "piece" and "clove" are distinct families.
        case count(String)
        /// Anything else ("pinch" today, any future unknown unit): summable
        /// only with itself, never dropped.
        case other(String)

        init(unit: String) {
            if GroceryListBuilder.massUnits[unit] != nil {
                self = .mass
            } else if GroceryListBuilder.volumeUnits[unit] != nil {
                self = .volume
            } else if GroceryListBuilder.countableUnits.contains(unit) {
                self = .count(unit)
            } else {
                self = .other(unit)
            }
        }

        /// Suffix for split-row ids ("potato#piece"). Never rendered in UI.
        var idSuffix: String {
            switch self {
            case .mass: return "mass"
            case .volume: return "volume"
            case .count(let unit), .other(let unit): return unit
            }
        }
    }

    /// Scaled total in the family's base unit (g / ml / the count unit
    /// itself) plus which source units contributed, for display selection.
    struct FamilyTotal {
        var baseTotal: Double = 0
        var sourceUnits: Set<String> = []
    }

    /// One canonical ingredient's consolidated, UNROUNDED totals across the week.
    struct Aggregate {
        var families: [UnitFamily: FamilyTotal] = [:]
        var category: String
        var mealCount = 0
    }

    /// Canonical consolidation: sum every ingredient across the week into
    /// unrounded base-unit totals (g / ml / count) per unit family, keyed by
    /// canonical English name. This is the single source of truth for BOTH the
    /// canonical grocery list (`build`) and the shopping-unit layer
    /// (`ShoppingListBuilder`) — deliberately shared so the two can never
    /// diverge over unit buckets, which is exactly what caused the historic
    /// silent undercount. Rounding and display-unit choice happen strictly
    /// after this, never during summation.
    static func aggregate(plan: WeekPlan, recipes: [Recipe], householdSize: Int) -> [String: Aggregate] {
        // Only the dishes the user actually intends to cook. A candidate they
        // did not select is not shopped for — that is the whole contract of the
        // selection sheet, and it is enforced here rather than in the view so
        // every surface (list, nudge count, share card) agrees.
        aggregate(recipeIDs: plan.meals.flatMap(\.selectedIDs), recipes: recipes, householdSize: householdSize)
    }

    /// The same consolidation for an explicit list of picked recipes (the
    /// Meal Seek paths: pick recipes → servings → grocery list).
    static func aggregate(recipeIDs: [String], recipes: [Recipe], householdSize: Int) -> [String: Aggregate] {
        let recipesByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var aggregates: [String: Aggregate] = [:]

        for recipeID in recipeIDs {
            guard let recipe = recipesByID[recipeID], recipe.baseServings > 0 else { continue }
            let scale = Double(householdSize) / Double(recipe.baseServings)

            // Deduped per DISH, not per slot: two selected dishes that both use
            // garlic consolidate into one row (the aggregate is keyed by name)
            // while still reporting that two meals need it.
            var namesSeenInThisMeal = Set<String>()
            for ingredient in recipe.ingredients where !neverShop.contains(ingredient.name) {
                var aggregate = aggregates[ingredient.name] ?? Aggregate(category: ingredient.category)
                if namesSeenInThisMeal.insert(ingredient.name).inserted {
                    aggregate.mealCount += 1
                }
                // Unit-less entries are always to-taste in the data (a
                // quantity never appears without a unit); they contribute
                // presence, not amount.
                if let quantity = ingredient.quantity, let unit = ingredient.unit {
                    let family = UnitFamily(unit: unit)
                    var total = aggregate.families[family] ?? FamilyTotal()
                    total.baseTotal += quantity * scale * baseMultiplier(for: unit, in: family)
                    total.sourceUnits.insert(unit)
                    aggregate.families[family] = total
                }
                aggregates[ingredient.name] = aggregate
            }
        }
        return aggregates
    }

    static func build(plan: WeekPlan, recipes: [Recipe], householdSize: Int) -> [GroceryItem] {
        let aggregates = aggregate(plan: plan, recipes: recipes, householdSize: householdSize)

        var items: [GroceryItem] = []
        for (name, aggregate) in aggregates {
            let quantified = aggregate.families.filter { $0.value.baseTotal > 0 }
            if quantified.isEmpty {
                // To-taste only (salt, black pepper): one bare row, as before.
                items.append(GroceryItem(
                    id: name, name: name, quantity: nil, unit: nil,
                    category: aggregate.category, recipeCount: aggregate.mealCount
                ))
                continue
            }
            // One row per family; the id stays the bare name unless the
            // ingredient genuinely splits, so existing bought state survives.
            let isSplit = quantified.count > 1
            for (family, total) in quantified {
                let (value, unit) = displayValue(for: family, total: total)
                items.append(GroceryItem(
                    id: isSplit ? "\(name)#\(family.idSuffix)" : name,
                    name: name,
                    quantity: rounded(value, unit: unit),
                    unit: unit,
                    category: aggregate.category,
                    recipeCount: aggregate.mealCount
                ))
            }
        }

        items.sort {
            let left = aisleRank($0.category)
            let right = aisleRank($1.category)
            if left != right { return left < right }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id // deterministic order for split rows
        }
        return items
    }

    /// Base-unit factor for summing: grams for mass, ml for volume, and the
    /// unit itself (factor 1) for counts and other units.
    static func baseMultiplier(for unit: String, in family: UnitFamily) -> Double {
        switch family {
        case .mass: return massUnits[unit] ?? 1
        case .volume: return volumeUnits[unit] ?? 1
        case .count, .other: return 1
        }
    }

    /// Picks the display unit and converts the base total into it.
    ///
    /// Volume follows the contributing-units rule: candidates are the units
    /// that actually contributed (plus "l" as the metric upgrade whenever
    /// "ml" did); the largest candidate keeping the value ≥ 1 wins, else the
    /// smallest. This keeps soy sauce in tbsp and broth in ml/l — never
    /// "16.7 tbsp" of milk. Mass upgrades g → kg at 1000.
    static func displayValue(for family: UnitFamily, total: FamilyTotal) -> (value: Double, unit: String) {
        switch family {
        case .mass:
            return total.baseTotal >= 1000 ? (total.baseTotal / 1000, "kg") : (total.baseTotal, "g")
        case .volume:
            var candidates = total.sourceUnits
            if candidates.contains("ml") { candidates.insert("l") }
            let largestFirst = candidates.sorted { (volumeUnits[$0] ?? 1) > (volumeUnits[$1] ?? 1) }
            let chosen = largestFirst.first { total.baseTotal / (volumeUnits[$0] ?? 1) >= 1 }
                ?? largestFirst.last ?? "ml"
            return (total.baseTotal / (volumeUnits[chosen] ?? 1), chosen)
        case .count(let unit), .other(let unit):
            return (total.baseTotal, unit)
        }
    }

    static func aisleRank(_ category: String) -> Int {
        aisleOrder.firstIndex(of: category) ?? aisleOrder.count - 1
    }

    /// Rounds a scaled-and-summed quantity to something buyable: countable
    /// units round up to whole; weight/volume rounds to the nearest 5 at ≥ 50,
    /// whole numbers at ≥ 10, and one decimal place below 10.
    static func rounded(_ value: Double, unit: String?) -> Double {
        if let unit, countableUnits.contains(unit) {
            return value.rounded(.up)
        }
        if value >= 50 { return (value / 5).rounded() * 5 }
        if value >= 10 { return value.rounded() }
        return (value * 10).rounded() / 10
    }
}
