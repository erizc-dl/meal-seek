//
//  GroceryItem.swift
//  Meal Seek
//
//  One line on the shopping list: an ingredient aggregated across every meal
//  in a week. Derived from the plan — never stored, never hand-edited.
//

import Foundation

struct GroceryItem: Identifiable, Hashable {
    /// Stable row identity and the bought-state key: the bare ingredient name
    /// while the ingredient is a single row, or "name#family" (e.g.
    /// "potato#piece") when incompatible unit families split the name into
    /// several rows. Internal only — the UI must never display an id; rows
    /// always show `name`.
    let id: String
    /// Canonical ingredient name — the dedup key across recipes, and the only
    /// name-like string that ever reaches the screen.
    let name: String
    /// Total scaled quantity in `unit`, or nil for to-taste items (salt,
    /// black pepper).
    let quantity: Double?
    let unit: String?
    /// The grocery aisle (the ingredient's `category`).
    let category: String
    /// How many meals in the week use this ingredient.
    let recipeCount: Int
    /// A pantry staple (salt, oils, dried spices, …): shown in the grocery list
    /// under its own "Check your pantry" section WITHOUT a computed quantity, so
    /// the shopper knows the week needs it without an absurd summed amount. This
    /// is a grocery-DISPLAY categorization only — allergen filtering and the
    /// recipe card read the canonical `Recipe` model and are unaffected. Defaults
    /// false so canonical consolidation (`GroceryListBuilder.build`) is unchanged.
    var isPantryStaple: Bool = false
    /// Total weight this row represents, in grams, when the shopping unit is a
    /// container whose size varies by shop — today only cans. Shown alongside
    /// the count ("2 can (~800 g)") so a shopper holding 250 g tins instead of
    /// 400 g ones can work out what to buy. nil whenever the unit already says
    /// everything (g, ml, piece, bunch). Defaults nil so canonical
    /// consolidation (`GroceryListBuilder.build`) is unchanged.
    var approximateGrams: Double? = nil
}

extension GroceryItem {
    /// Quantity for display: "600 g", "2 can (~800 g)", "6" (pieces read best
    /// bare), or nil for to-taste items so the row shows no quantity at all.
    var displayQuantity: String? {
        guard let quantity else { return nil }
        let number = quantity == quantity.rounded() ? String(Int(quantity)) : String(quantity)
        guard let unit, unit != "piece" else { return number }
        return "\(number) \(unit)\(Self.weightSuffix(approximateGrams))"
    }

    /// " (~800 g)" / " (~1.2 kg)", or "" when there is no weight to add. Pure
    /// symbols and digits, so it renders identically in every language.
    static func weightSuffix(_ grams: Double?) -> String {
        guard let grams, grams > 0 else { return "" }
        if grams >= 1000 {
            let kg = (grams / 100).rounded() / 10          // one decimal
            let text = kg == kg.rounded() ? String(Int(kg)) : String(kg)
            return " (~\(text) kg)"
        }
        return " (~\(Int(grams.rounded())) g)"
    }
}
