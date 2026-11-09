//
//  GroceryPlanner.swift
//  Meal Seek
//
//  The grocery list for the recipes a user picked (all three paths →
//  Servings → Grocery). Builds on ShoppingListBuilder (scaling, merging,
//  pantry staples with no quantity, whole produce, bunches, cans) and adds the
//  owner's rule on top:
//
//    EVERY ingredient is shown as a whole number of things you can buy,
//    EXCEPT meat and seafood, which keep their weight in the user's units.
//
//  So "355 g spinach" becomes "1 bag spinach · uses ~355 g", "15 g garlic"
//  becomes "1 head garlic", "45 ml soy sauce" becomes "1 bottle soy sauce".
//  Package sizes are typical supermarket sizes; the "uses" note keeps the real
//  amount visible for anyone holding a different size.
//

import Foundation

enum MeasurementSystem: String, Codable, CaseIterable {
    case metric
    case imperial
}

enum GroceryPlanner {
    struct GroceryPlan {
        /// Every picked recipe together.
        let all: [GroceryItem]
        /// One list per recipe, in pick order (the per-recipe tabs).
        let byRecipe: [(recipeID: String, items: [GroceryItem])]
    }

    static func build(
        recipeIDs: [String],
        recipes: [Recipe],
        servings: Int,
        units: MeasurementSystem
    ) -> GroceryPlan {
        var unique: [String] = []
        for id in recipeIDs where !unique.contains(id) { unique.append(id) }
        let servings = max(1, servings)
        let list = { (ids: [String]) in
            ShoppingListBuilder.build(recipeIDs: ids, recipes: recipes, servings: servings)
                .map { buyable($0, units: units) }
        }
        return GroceryPlan(all: list(unique), byRecipe: unique.map { ($0, list([$0])) })
    }

    // MARK: Packages

    /// A thing you buy and how much is in one (grams, or ml for liquids).
    struct Package {
        let unit: String
        let size: Double
    }

    /// Ingredient-specific packages. Anything not listed falls back to its
    /// aisle's default (`defaultPackage`).
    static let packages: [String: Package] = [
        // spices & aromatics bought whole
        "garlic": Package(unit: "head", size: 40),
        "ginger": Package(unit: "knob", size: 50),
        "galangal": Package(unit: "knob", size: 50),
        "garlic chives": Package(unit: "bunch", size: 100),
        "mitsuba": Package(unit: "bunch", size: 50),
        // grains, flours, sugar: big bags
        "rice": Package(unit: "bag", size: 1000), "jasmine rice": Package(unit: "bag", size: 1000),
        "basmati rice": Package(unit: "bag", size: 1000), "short-grain rice": Package(unit: "bag", size: 1000),
        "sticky rice": Package(unit: "bag", size: 1000), "arborio rice": Package(unit: "bag", size: 500),
        "carnaroli rice": Package(unit: "bag", size: 500), "idli rice": Package(unit: "bag", size: 1000),
        "all-purpose flour": Package(unit: "bag", size: 1000), "bread flour": Package(unit: "bag", size: 1000),
        "whole wheat flour": Package(unit: "bag", size: 1000), "masa harina": Package(unit: "bag", size: 1000),
        "cornmeal": Package(unit: "bag", size: 500), "polenta": Package(unit: "bag", size: 500),
        "semolina": Package(unit: "bag", size: 500), "rolled oats": Package(unit: "bag", size: 500),
        "cooked rice": Package(unit: "bag", size: 1000), "cooked jasmine rice": Package(unit: "bag", size: 1000),
        // dairy
        "butter": Package(unit: "block", size: 250), "ghee": Package(unit: "jar", size: 400),
        "yogurt": Package(unit: "tub", size: 500), "greek yogurt": Package(unit: "tub", size: 500),
        "sour cream": Package(unit: "tub", size: 250), "crema": Package(unit: "tub", size: 250),
        "ricotta": Package(unit: "tub", size: 250), "milk": Package(unit: "carton", size: 1000),
        "almond milk": Package(unit: "carton", size: 1000), "cream": Package(unit: "carton", size: 250),
        "heavy cream": Package(unit: "carton", size: 250),
        // tofu
        "tofu": Package(unit: "block", size: 400), "firm tofu": Package(unit: "block", size: 400),
        "soft tofu": Package(unit: "block", size: 400),
        // bread
        "bread": Package(unit: "loaf", size: 500), "crusty bread": Package(unit: "loaf", size: 500),
        "sandwich bread": Package(unit: "loaf", size: 500), "sourdough bread": Package(unit: "loaf", size: 500),
        "rye bread": Package(unit: "loaf", size: 500), "brioche bread": Package(unit: "loaf", size: 400),
        "ciabatta bread": Package(unit: "loaf", size: 300),
        // liquids
        "beef broth": Package(unit: "carton", size: 1000), "chicken broth": Package(unit: "carton", size: 1000),
        "vegetable broth": Package(unit: "carton", size: 1000), "broth": Package(unit: "carton", size: 1000),
        "fish stock": Package(unit: "carton", size: 1000), "dashi": Package(unit: "carton", size: 1000),
        "anchovy broth": Package(unit: "carton", size: 1000), "tonkotsu broth": Package(unit: "carton", size: 1000),
        "dry red wine": Package(unit: "bottle", size: 750), "white wine": Package(unit: "bottle", size: 750),
        "beer": Package(unit: "bottle", size: 330), "sake": Package(unit: "bottle", size: 720),
        "green tea": Package(unit: "box", size: 1000), "black tea": Package(unit: "box", size: 1000),
        "coffee": Package(unit: "bag", size: 250),
        // sliced
        "cheese#slice": Package(unit: "pack", size: 10), "cheddar#slice": Package(unit: "pack", size: 10),
        "pickles#slice": Package(unit: "jar", size: 20), "pineapple#slice": Package(unit: "can", size: 10),
    ]

    /// What a weighed or measured ingredient comes in when it has no entry above.
    static func defaultPackage(category: String, isLiquid: Bool) -> Package {
        switch (category, isLiquid) {
        case ("produce", false): return Package(unit: "pack", size: 250)
        case ("dairy_eggs", false): return Package(unit: "pack", size: 200)
        case ("pantry", false): return Package(unit: "pack", size: 500)
        case ("bakery", false): return Package(unit: "pack", size: 400)
        case ("frozen", false): return Package(unit: "bag", size: 500)
        case ("condiments", false): return Package(unit: "jar", size: 300)
        case ("spices_seasonings", false): return Package(unit: "pack", size: 50)
        case ("beverages", true): return Package(unit: "bottle", size: 750)
        case ("dairy_eggs", true): return Package(unit: "carton", size: 500)
        case (_, true): return Package(unit: "bottle", size: 250)
        default: return Package(unit: "pack", size: 250)
        }
    }

    /// Countable units that are already something you buy. Slices are not:
    /// "6 slice cheddar" becomes a pack.
    static let alreadyBuyable: Set<String> = ["piece", "can", "bunch", "clove"]

    // MARK: Conversion

    static let gramsPerUnit: [String: Double] = ["g": 1, "kg": 1000]
    static let mlPerUnit: [String: Double] = ["ml": 1, "l": 1000, "tsp": 5, "tbsp": 15]

    /// One shopping row → whole buyable things (or a meat weight).
    static func buyable(_ item: GroceryItem, units: MeasurementSystem) -> GroceryItem {
        guard !item.isPantryStaple, let quantity = item.quantity, let unit = item.unit else { return item }

        if let grams = gramsPerUnit[unit].map({ $0 * quantity }) {
            if item.category == "meat_seafood" {
                let (value, shown) = weight(grams, units: units)
                return with(item, quantity: value, unit: shown)
            }
            return packaged(item, base: grams, isLiquid: false, units: units)
        }
        if let ml = mlPerUnit[unit].map({ $0 * quantity }) {
            return packaged(item, base: ml, isLiquid: true, units: units)
        }
        if unit == "slice" {
            let package = packages["\(item.name)#slice"] ?? Package(unit: "pack", size: 10)
            return with(item, quantity: (quantity / package.size).rounded(.up), unit: package.unit,
                        needed: "\(Int(quantity)) slices")
        }
        if unit == "can", units == .imperial, let grams = item.approximateGrams {
            var out = item
            out.approximateGrams = nil
            out.neededAmount = weightText(grams, units: .imperial)
            return out
        }
        return item // piece, bunch, clove, pinch: already whole things
    }

    private static func packaged(_ item: GroceryItem, base: Double, isLiquid: Bool, units: MeasurementSystem) -> GroceryItem {
        let package = packages[item.name] ?? defaultPackage(category: item.category, isLiquid: isLiquid)
        let count = max(1, (base / package.size - 0.0001).rounded(.up))
        let needed = isLiquid ? volumeText(base, units: units) : weightText(base, units: units)
        return with(item, quantity: count, unit: package.unit, needed: needed)
    }

    private static func with(_ item: GroceryItem, quantity: Double, unit: String, needed: String? = nil) -> GroceryItem {
        var out = GroceryItem(
            id: item.id, name: item.name, quantity: quantity, unit: unit,
            category: item.category, recipeCount: item.recipeCount, isPantryStaple: item.isPantryStaple
        )
        out.neededAmount = needed
        return out
    }

    /// Meat weight in the user's units, rounded UP so it's never under-bought:
    /// metric keeps ShoppingListBuilder's grams (kg from 1000 g); imperial uses
    /// whole ounces under a pound, then quarter pounds.
    static func weight(_ grams: Double, units: MeasurementSystem) -> (Double, String) {
        switch units {
        case .metric:
            return grams >= 1000 ? ((grams / 100).rounded(.up) / 10, "kg") : (grams.rounded(.up), "g")
        case .imperial:
            let ounces = max(1, (grams / 28.3495 - 0.0001).rounded(.up))
            if ounces < 16 { return (ounces, "oz") }
            return ((grams / 453.592 * 4 - 0.0001).rounded(.up) / 4, "lb")
        }
    }

    /// "~355 g" / "~1.2 kg" / "~13 oz" / "~1.5 lb" for the "uses" note.
    static func weightText(_ grams: Double, units: MeasurementSystem) -> String {
        let (value, unit) = units == .metric && grams < 1000
            ? (grams.rounded(), "g")
            : weight(grams, units: units)
        return "~\(number(value)) \(unit)"
    }

    /// "~45 ml" / "~1.2 l" / "~3 tbsp" / "~1.5 cups".
    static func volumeText(_ ml: Double, units: MeasurementSystem) -> String {
        switch units {
        case .metric:
            return ml >= 1000 ? "~\(number((ml / 100).rounded() / 10)) l" : "~\(number(ml.rounded())) ml"
        case .imperial:
            if ml < 60 { return "~\(number(max(1, (ml / 15).rounded()))) tbsp" }
            let cups = (ml / 236.6 * 4).rounded() / 4
            return "~\(number(cups)) \(cups == 1 ? "cup" : "cups")"
        }
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
