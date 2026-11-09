//
//  RecipeTranslation.swift
//  Meal Seek
//
//  Codable models for the DISPLAY-LAYER translation files. The canonical English
//  recipe database (Recipe.swift) is never touched: these files are keyed by
//  canonical recipe id and canonical English ingredient name, and every field is
//  optional so a missing recipe / ingredient / step falls back to English.
//
//  Two file shapes per language:
//    • recipes.<lang>.json      — per-recipe name, ingredient names, steps
//    • recipe-terms.<lang>.json — global preparation + word-unit vocabulary
//
//  See RecipeTranslationStore for loading, fallback, and the display-only rule.
//

import Foundation

/// One recipe's translation. All fields optional → partial translations render.
struct RecipeTranslation: Codable {
    /// Localized recipe name, or nil to fall back to the English name.
    let name: String?
    /// Canonical English ingredient name → localized display name. A name absent
    /// here falls back to English. Duplicate ingredient rows share one entry.
    let ingredients: [String: String]?
    /// Positional with the canonical `instructions`. A nil element, or an array
    /// shorter than the canonical step list, falls back to English for that step.
    let instructions: [String?]?
}

/// The per-language recipe translation file (recipes.<lang>.json).
struct RecipeTranslationFile: Codable {
    struct Metadata: Codable {
        let schemaVersion: Int
        let sourceLanguage: String
        let targetLanguage: String
        let translatedRecipeCount: Int
    }
    let metadata: Metadata
    /// Canonical recipe id → translation. An object (not an array) so recipe
    /// reordering in the English DB can never corrupt it, and batches merge.
    let recipes: [String: RecipeTranslation]
}

/// The global term file (recipe-terms.<lang>.json): context-free preparation and
/// word-unit renderings shared by every recipe. Symbol units (g/kg/ml/l) are
/// international and deliberately absent — they always display as canonical.
struct RecipeTermsFile: Codable {
    struct Metadata: Codable {
        let schemaVersion: Int
        let sourceLanguage: String
        let targetLanguage: String
    }
    let metadata: Metadata
    /// Canonical English preparation ("diced") → localized ("切丁"). For Spanish
    /// this is the masculine-singular form; the agreeing forms live in
    /// `preparationForms` and take precedence when present.
    let preparations: [String: String]
    /// Canonical English word-unit ("tbsp") → localized ("汤匙").
    let units: [String: String]
    /// Spanish only (absent for zh-Hans): grammatical gender + default number of
    /// each ingredient, keyed by canonical English name. Lets the assembler
    /// inflect an adjectival preparation to agree with the ingredient.
    let ingredientGrammar: [String: IngredientGrammar]?
    /// Spanish only (absent for zh-Hans): the four inflected forms of every
    /// adjectival preparation. A preparation absent here is invariable and uses
    /// its single `preparations` rendering.
    let preparationForms: [String: PreparationForms]?
}

/// An ingredient's Spanish grammatical agreement data.
struct IngredientGrammar: Codable {
    /// "m" or "f".
    let gender: String
    /// "s" (singular) or "p" (plural) — the ingredient's default number.
    let number: String
}

/// The four gender/number inflections of an adjectival preparation.
struct PreparationForms: Codable {
    let ms: String
    let fs: String
    let mp: String
    let fp: String

    /// The form agreeing with the given gender ("m"/"f") and number ("s"/"p").
    func form(gender: String, plural: Bool) -> String {
        switch (gender, plural) {
        case ("f", false): return fs
        case ("m", true): return mp
        case ("f", true): return fp
        default: return ms
        }
    }
}
