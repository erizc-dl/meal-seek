//
//  RecipeScaling+Environment.swift
//  Meal Seek
//
//  SwiftUI plumbing for RecipeScaling, kept apart from the scaling itself so
//  that file stays Foundation-only and can be exercised by the standalone logic
//  harnesses, which cannot link the SwiftUI app lifecycle. Same split, and for
//  the same reason, as RecipeTranslationStore+Environment.swift.
//

import SwiftUI

private struct CookingServingsKey: EnvironmentKey {
    /// No household in scope. Previews and the onboarding flow then show a
    /// recipe with the amounts it was authored with, which is the honest
    /// reading when there is no preference to scale to yet.
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// How many people the user is cooking for — `UserPreferences.householdSize`,
    /// injected once at the app root and read at the view layer only, exactly
    /// like `recipeTranslations`. The canonical recipe is never rewritten.
    var cookingServings: Int? {
        get { self[CookingServingsKey.self] }
        set { self[CookingServingsKey.self] = newValue }
    }
}
