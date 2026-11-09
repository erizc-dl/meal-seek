//
//  LocalizedNames.swift
//  Meal Seek
//
//  The single source for display-name localization of values that are stored
//  and matched in canonical English. Cuisine, region, meal-type, allergen, and
//  grocery-aisle KEYS never change — they drive all matching, filtering, and
//  grouping. Only the rendered label is localized here, via the app's String
//  Catalog. If a key is missing a translation, the English key is the fallback,
//  so nothing ever renders blank.
//
//  Weekday labels are localized too, but their Monday-first ORDER is pinned
//  independently of the locale's firstWeekday: the label is cosmetic, while
//  dayIndex 0 is always Monday in the plan data. See the cross-locale test in
//  tests/main.swift.
//

import Foundation

enum LocalizedNames {
    /// Localized cuisine label for a canonical cuisine key (e.g. "Italian").
    static func cuisine(_ key: String) -> String {
        NSLocalizedString("cuisine.\(key)", value: key, comment: "Cuisine display name")
    }

    /// Localized region label for a canonical region key (e.g. "European").
    static func region(_ key: String) -> String {
        NSLocalizedString("region.\(key)", value: key, comment: "Region display name")
    }

    /// Localized meal-type label for a meal-type key ("breakfast"/"lunch"/"dinner").
    static func mealType(_ key: String) -> String {
        NSLocalizedString("mealtype.\(key)", value: key.capitalized, comment: "Meal type display name")
    }

    /// Localized allergen label for a canonical allergen value (e.g. "tree_nut").
    static func allergen(_ value: String) -> String {
        NSLocalizedString("allergen.\(value)", value: value.capitalized, comment: "Allergen display name")
    }

    /// Localized dish-role label for a `DishRole` raw value (e.g. "staple").
    ///
    /// Every role has a label here, including `all_in_one` — the Add Recipe
    /// picker offers it as a choice and has to name it. Whether a role is
    /// LABELLED ON A MEAL CARD is a different question; `cardRole(_:)` answers
    /// that one.
    static func role(_ value: String) -> String {
        NSLocalizedString("role.\(value)", value: value.capitalized, comment: "Dish role display name")
    }

    /// The label a meal card shows for a dish's role, or nil for a role that is
    /// never labelled on a card.
    ///
    /// `allInOne` returns nil because it IS the meal — saying so adds a line to
    /// the row and tells the user nothing they did not already know from it
    /// being the only dish. `unassigned` returns nil because it is an absence,
    /// not a fact worth rendering.
    ///
    /// This lives beside the localization rather than on `DishRole` itself so
    /// the model stays dependency-free: `tests/dish-role-audit` compiles
    /// `DishRole.swift` with `Recipe.swift` and nothing else, and that minimal
    /// source list is what keeps the data layer honest.
    static func cardRole(_ role: DishRole) -> String? {
        switch role {
        case .staple, .main, .side: return self.role(role.rawValue)
        case .allInOne, .unassigned: return nil
        }
    }

    /// Localized grocery-aisle label for an ingredient category key.
    static func aisle(_ category: String) -> String {
        NSLocalizedString("aisle.\(category)", value: category.capitalized, comment: "Grocery aisle display name")
    }

    // MARK: Weekday labels — localized text, ALWAYS Monday-first

    /// Very-short weekday labels (en M T W T F S S / es L M X J V S D /
    /// zh 一 二 三 四 五 六 日), indexed 0 = Monday … 6 = Sunday regardless of the
    /// locale's firstWeekday. Used by the Home week strip.
    static func veryShortWeekdayLabels(locale: Locale = .current) -> [String] {
        mondayFirst(gregorianSymbols(locale: locale, \.veryShortWeekdaySymbols))
    }

    /// Abbreviated weekday labels (en Mon / es lun. / zh 周一), Monday-first.
    /// Used by the shareable week card.
    static func shortWeekdayLabels(locale: Locale = .current) -> [String] {
        mondayFirst(gregorianSymbols(locale: locale, \.shortWeekdaySymbols))
    }

    /// Gregorian weekday-symbol arrays are always Sunday-indexed (index 0 =
    /// Sunday) independent of firstWeekday, so we can safely re-key them to
    /// Monday-first ourselves.
    private static func gregorianSymbols(locale: Locale, _ keyPath: KeyPath<Calendar, [String]>) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar[keyPath: keyPath]
    }

    /// Re-key a Sunday-first symbol array to Monday-first: index i (0 = Monday)
    /// maps to Gregorian weekday symbol (i + 1) mod 7. Pinned — never derived
    /// from `Calendar.firstWeekday`.
    private static func mondayFirst(_ sundayFirst: [String]) -> [String] {
        guard sundayFirst.count == 7 else { return sundayFirst }
        return (0..<7).map { sundayFirst[($0 + 1) % 7] }
    }
}
