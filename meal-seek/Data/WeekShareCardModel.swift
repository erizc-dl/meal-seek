//
//  WeekShareCardModel.swift
//  Meal Seek
//
//  The label logic for WeekShareCard's meal rows, extracted so it is
//  Foundation-only and covered by the translation harness. The share card is
//  rasterized off-screen by ImageRenderer, OUTSIDE the app's SwiftUI
//  environment, so its translation wiring can't be exercised by touching the
//  running app — a wrong name would surface only in the exported image. Keeping
//  the resolution here lets a plain logic test lock it in.
//
//  DISPLAY-ONLY: resolves the slot's recipe by canonical id, then returns the
//  active-language name via the store (English fallback). Identity stays English.
//

import Foundation

enum WeekShareCardModel {
    /// Every dish the user chose for one slot, in candidate order, each in the
    /// active language — or a single `emptyPlaceholder` entry when the slot is
    /// empty or none of its ids resolve. Never empty, so a caller can render the
    /// result directly without a hole.
    ///
    /// Walks `selectedIDs`, NOT `candidateIDs`. The dishes a user considered and
    /// rejected are private planning state; a card they hand to someone else
    /// must show only what they actually intend to cook. That distinction lives
    /// here, in the one function the card's text comes from, so there is exactly
    /// one place it could ever be got wrong.
    static func mealLabels(
        for mealType: String,
        onDay dayIndex: Int,
        in plan: WeekPlan,
        recipes: [Recipe],
        translations: RecipeTranslationStore,
        emptyPlaceholder: String
    ) -> [String] {
        guard let meal = plan.meal(ofType: mealType, onDay: dayIndex) else {
            return [emptyPlaceholder]
        }
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // An id with no recipe (a deleted user recipe) drops out rather than
        // rendering blank; if that empties the slot, the placeholder stands in.
        let names = meal.selectedIDs.compactMap { byID[$0] }.map { translations.name(for: $0) }
        return names.isEmpty ? [emptyPlaceholder] : names
    }

    /// The slot's headline dish alone. Retained for callers that need a single
    /// line (and for the label tests); the card itself renders `mealLabels`.
    static func mealLabel(
        for mealType: String,
        onDay dayIndex: Int,
        in plan: WeekPlan,
        recipes: [Recipe],
        translations: RecipeTranslationStore,
        emptyPlaceholder: String
    ) -> String {
        mealLabels(
            for: mealType, onDay: dayIndex, in: plan, recipes: recipes,
            translations: translations, emptyPlaceholder: emptyPlaceholder
        )[0]
    }
}
