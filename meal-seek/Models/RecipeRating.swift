//
//  RecipeRating.swift
//  Meal Seek
//
//  An explicit thumbs-up/thumbs-down rating for a recipe. Unrated is the
//  absence of a record, never a stored case.
//

import Foundation

enum RecipeRating: String, Codable {
    case liked
    case disliked
}
