//
//  RecipeTranslationStore+Environment.swift
//  Meal Seek
//
//  SwiftUI plumbing for RecipeTranslationStore, kept apart from the store itself
//  so the store stays Foundation-only and can be exercised by the standalone
//  logic harness (tests/translation-tests.swift), which cannot link the SwiftUI
//  app lifecycle.
//

import SwiftUI

private struct RecipeTranslationStoreKey: EnvironmentKey {
    /// English fallback store — used by previews / any view read before the app
    /// injects the real one. Loads nothing.
    static let defaultValue = RecipeTranslationStore(language: nil)
}

extension EnvironmentValues {
    /// The active-language translation store, injected once at the app root and
    /// read at the view layer only.
    var recipeTranslations: RecipeTranslationStore {
        get { self[RecipeTranslationStoreKey.self] }
        set { self[RecipeTranslationStoreKey.self] = newValue }
    }
}
