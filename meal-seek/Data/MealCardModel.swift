//
//  MealCardModel.swift
//  Meal Seek
//
//  The pure derivation behind the Home screen's meal card, kept out of the view
//  so it can be tested directly — the same arrangement as WeekShareCardModel,
//  and for the same reason: the rule about which dishes a slot shows is worth
//  asserting, and a SwiftUI body cannot be asserted against.
//

import Foundation

enum MealCardModel {
    /// The dishes a slot should render, resolved and in `selectedIDs` order.
    ///
    /// Resolution is per DISH. An id with no recipe behind it — a user recipe
    /// deleted while it sat in a plan — drops out and its siblings still render.
    /// The card falls back to its empty state only when this returns empty,
    /// i.e. when NOTHING in the slot resolves.
    ///
    /// This matches what `WeekShareCardModel.mealLabels` and
    /// `GroceryListBuilder.aggregate` already do with an unresolvable id. The
    /// Home card used to differ: it keyed off the slot's headline dish alone, so
    /// one stale id blanked the whole card while the share card and the grocery
    /// list still listed the slot's other dishes correctly.
    static func dishes(for meal: PlannedMeal?, recipes: [Recipe]) -> [Recipe] {
        guard let meal else { return [] }
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return meal.selectedIDs.compactMap { byID[$0] }
    }
}
