//
//  IngredientMatcher.swift
//  Meal Seek
//
//  Decides whether something the user has in the fridge counts as a recipe
//  ingredient (Path 1). Names are compared word by word, never with plain
//  `contains`, so "egg" never matches "eggplant".
//
//  The rule: after aliases and simple plurals, one name's words must appear
//  as a run inside the other's, and the leftover words must not turn it into a
//  different product. "chicken" matches "chicken thigh" and "whole chicken",
//  "rice" matches "jasmine rice", "tomato" matches "cherry tomatoes"; but
//  "chicken" does NOT match "chicken broth", "rice" does NOT match
//  "rice noodles", and fresh "tomato" does NOT match "canned tomato".
//

import Foundation

enum IngredientMatcher {
    /// Things every kitchen is assumed to have. They never count as a match
    /// and are never listed as missing, so "salt" can't make a recipe look
    /// like a better fit. They still go on the grocery list.
    static let assumedPantry: Set<String> = ["water", "salt", "black pepper", "vegetable oil", "olive oil"]

    /// Leftover words that make a different product out of the shared word
    /// ("chicken" + "broth"). Singular, lowercased.
    static let productWords: Set<String> = [
        "broth", "stock", "sauce", "paste", "powder", "flour", "vinegar", "oil",
        "noodle", "cake", "wine", "syrup", "starch", "milk", "bun", "roll",
        "wrapper", "gelatin", "fat", "bone", "jam", "chip", "crisp", "roux",
        "pastry", "flake", "extract", "sprout", "leaf", "leave", "husk", "casing",
        "curd", "crouton", "glace", "cracker", "muffin", "tea", "sugar", "ball",
        "pouch", "seed", "canned", "pickled", "dried", "juice", "sour", "breadcrumb",
        "tortilla", "pesto", "mashed", "cooked", "fried", "smoked", "salt",
        "chorizo", "sausage", "shank", "trotter", "knuckle", "tripe", "skin",
    ]

    /// Different foods that happen to contain another food's name. Each one
    /// matches only itself: "butter" is not "peanut butter", "potato" is not
    /// "sweet potato", "egg" is not "century egg".
    static let distinctFoods: Set<String> = [
        "peanut butter", "sweet potato", "water spinach", "century egg",
        "mustard greens", "turnip greens", "squid ink", "cilantro root",
        "garlic chives", "salt cod", "salt pork", "potato gnocchi",
        "rice vermicelli", "chinese broccoli", "corned beef", "roasted red pepper",
        "almond milk", "coconut milk", "soy milk", "oat milk",
    ]

    /// Names that are the same thing to a shopper, mapped to one spelling.
    static let aliases: [String: String] = [
        "lemon juice": "lemon",
        "lime juice": "lime",
        "orange juice": "orange",
        "cooked rice": "rice",
        "cooked jasmine rice": "jasmine rice",
        "parmigiano reggiano": "parmesan",
        "gruyere cheese": "gruyere",
        "scallion": "green onion",
        "spring onion": "green onion",
        "coriander leaves": "cilantro",
        "aubergine": "eggplant",
        "courgette": "zucchini",
        "prawn": "shrimp",
        "egg yolk": "egg",
    ]

    /// True when the user's ingredient `have` counts as the recipe's `needed`.
    static func matches(_ have: String, _ needed: String) -> Bool {
        matches(words: words(of: have), words: words(of: needed))
    }

    /// The same test on names already split by `words(of:)`, so a caller
    /// comparing many names splits each one only once.
    static func matches(words a: [String], words b: [String]) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if isDistinct(a) || isDistinct(b) { return false }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard short.count < long.count else { return false }
        for start in 0...(long.count - short.count) where Array(long[start..<start + short.count]) == short {
            let leftover = long[..<start] + long[(start + short.count)...]
            if leftover.allSatisfy({ !productWords.contains($0) }) { return true }
        }
        return false
    }

    /// Lowercased, alias-resolved, singular words of a name.
    static func words(of name: String) -> [String] {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = aliases[lower] ?? aliases[singularPhrase(lower)] ?? lower
        return resolved
            .split(whereSeparator: { !$0.isLetter })
            .map { singular(String($0)) }
    }

    private static let distinctWords: Set<[String]> = Set(distinctFoods.map { words(of: $0) })

    private static func isDistinct(_ words: [String]) -> Bool {
        distinctWords.contains(words)
    }

    private static func singularPhrase(_ phrase: String) -> String {
        phrase.split(separator: " ").map { singular(String($0)) }.joined(separator: " ")
    }

    /// Rough English singular, applied the same way on both sides, so it only
    /// has to be consistent, not correct ("asparagus" → "asparagu" is fine).
    static func singular(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 4, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }
}
