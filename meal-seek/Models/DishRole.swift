//
//  DishRole.swift
//  Meal Seek
//
//  What part of a meal a dish plays. Data-layer metadata only: nothing in
//  generation, the UI, or grocery aggregation reads it yet. It exists so
//  slot-based generation can later fill a lunch or dinner slot with a
//  COMPOSED meal — a main plus a side plus a staple — instead of picking one
//  dish and calling it dinner.
//
//  `unassigned` is the default and is never written by the derivation pass.
//  It is what an older `user-recipes.json`, an older backup archive, or a
//  future role this build has not heard of decodes to, so no existing data
//  and no saved plan can fail to load because of this field. A standing audit
//  (`tests/dish-role-audit`) asserts no BUNDLED recipe carries it.
//
//  Raw values are snake_case to match every other string enum in the data
//  (`tree_nut`, `meat_seafood`, `high_protein`).
//

import Foundation

enum DishRole: String, Codable, CaseIterable, Hashable {
    /// A carbohydrate base that is cooked and served alongside, not eaten
    /// alone: steamed rice, plain naan, tortillas, boiled noodles.
    case staple

    /// The dish a meal is named after — the protein or the centrepiece.
    case main

    /// A vegetable dish, salad, or soup that accompanies a main. Soups are
    /// sides that additionally set `isSoup`.
    case side

    /// A complete meal in one vessel: a stew over its own rice, a noodle
    /// bowl, a burrito, a sandwich. Needs no main, side, or staple beside it.
    case allInOne = "all_in_one"

    /// No role has been assigned. The default, and a hard failure for a
    /// bundled recipe.
    case unassigned

    /// Every role the derivation pass and the coverage matrix work in —
    /// `allCases` minus the default. Ordered as a plate is composed.
    static let assignable: [DishRole] = [.main, .side, .staple, .allInOne]

    /// Decodes an unrecognised raw value to `.unassigned` rather than
    /// throwing. A build that meets a role added by a newer build must still
    /// load the user's recipes and plans.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DishRole(rawValue: raw) ?? .unassigned
    }

    /// Roles a user may pick for their own recipe, in the order the Add Recipe
    /// chips render them: the three composing parts, then the whole meal.
    ///
    /// `unassigned` is deliberately absent — it is what an older file decodes
    /// to, never something a user chooses. A recipe saved with it is invisible
    /// to slot-based generation, which is the whole reason the field is asked
    /// for at all.
    static let userSelectable: [DishRole] = [.staple, .main, .side, .allInOne]
}
