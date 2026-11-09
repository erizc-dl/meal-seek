//
//  FeedbackEvent.swift
//  Meal Seek
//
//  One meal-swap signal: a recipe the user rejected from (or chose into) a
//  slot. Accumulated append-only in feedback.json; nothing reads it yet.
//

import Foundation

enum FeedbackAction: String, Codable {
    /// The user emptied a slot holding this recipe.
    case removed
    /// The user replaced this recipe with another one.
    case replacedAway
    /// The user chose this recipe from the picker (fill or replacement).
    case added
}

struct FeedbackEvent: Codable {
    let recipeId: String
    /// "breakfast", "lunch", or "dinner" — the slot the action happened in.
    let mealType: String
    let action: FeedbackAction
    /// When the action happened.
    let date: Date
    /// The Monday of the week whose plan was edited.
    let weekStartDate: Date
}
