//
//  WeekGenerationError.swift
//  Meal Seek
//
//  The outcome vocabulary for week generation. `PlanGenerator.generate` now
//  returns a `Result<WeekGenerationOutcome, WeekGenerationError>` so a failure
//  is never a silent empty week, and a *partial* week (some meal types couldn't
//  be filled) still returns the valid work it did produce alongside a
//  non-blocking warning.
//
//  Nothing in here imports SwiftUI: the user-facing copy is plain strings the
//  views render, and the raw `diagnosticDescription` is for the shared bug
//  report only — never shown to the user.
//

import Foundation

/// Why a week couldn't be generated at all. Every case is a *hard* failure:
/// the generator produced no usable plan. A week that filled some but not all
/// slots is a success carrying a `WeekGenerationWarning`, not one of these.
enum WeekGenerationError: Error, Equatable {
    /// The user's cuisine/allergy settings rule out every recipe — the pool is
    /// empty before a single slot can be considered.
    case noRecipesMatchFilters
    /// Recipes survived filtering but too few fit the daily meal types to fill
    /// even one slot. `available` is the size of the allergen-safe pool.
    case insufficientRecipes(needed: Int, available: Int)
    /// The bundled recipe database failed to load or decode, so there is
    /// nothing to plan from. `underlying` carries the loader's own reason for
    /// the diagnostic — never surfaced to the user.
    case databaseLoadFailed(underlying: String)
    /// Defensive catch-all so an unexpected internal state fails loudly (with a
    /// report) instead of silently.
    case unknown(underlying: String)

    /// Which primary action the error screen should offer.
    enum PrimaryAction {
        /// Send the user to loosen their cuisine/allergy settings.
        case adjustPreferences
        /// Retry generation (transient/unexpected failures).
        case tryAgain
    }

    var primaryAction: PrimaryAction {
        switch self {
        case .noRecipesMatchFilters, .insufficientRecipes:
            return .adjustPreferences
        case .databaseLoadFailed, .unknown:
            return .tryAgain
        }
    }

    /// The button label matching `primaryAction`.
    var primaryActionTitle: String {
        switch primaryAction {
        case .adjustPreferences: return String(localized: "Adjust Preferences")
        case .tryAgain: return String(localized: "Try Again")
        }
    }

    /// Plain-language headline. Deliberately contains no raw Swift error text.
    var userHeadline: String {
        switch self {
        case .noRecipesMatchFilters: return String(localized: "No recipes match your choices")
        case .insufficientRecipes:   return String(localized: "Not enough recipes for a full week")
        case .databaseLoadFailed:    return String(localized: "We couldn't load the recipe library")
        case .unknown:               return String(localized: "Something went wrong")
        }
    }

    /// One sentence explaining the likely cause in the user's terms.
    var userExplanation: String {
        switch self {
        case .noRecipesMatchFilters:
            return String(localized: "Your cuisine and allergy settings rule out every recipe. Loosening them will give us something to plan.")
        case .insufficientRecipes:
            return String(localized: "Too few recipes fit your current settings to fill a week. Adding cuisines or removing an allergy will help.")
        case .databaseLoadFailed:
            return String(localized: "The recipe library didn't load, so there's nothing to build a week from. Trying again usually fixes it.")
        case .unknown:
            return String(localized: "We hit an unexpected problem while building your week. Trying again usually fixes it.")
        }
    }

    /// A stable, machine-readable rendering of the case and its associated
    /// values, for the diagnostic report only. Never shown to the user.
    var diagnosticDescription: String {
        switch self {
        case .noRecipesMatchFilters:
            return "noRecipesMatchFilters"
        case let .insufficientRecipes(needed, available):
            return "insufficientRecipes(needed: \(needed), available: \(available))"
        case let .databaseLoadFailed(underlying):
            return "databaseLoadFailed(underlying: \(underlying))"
        case let .unknown(underlying):
            return "unknown(underlying: \(underlying))"
        }
    }
}

/// A non-blocking notice attached to an otherwise-successful generation: the
/// plan is valid and usable, but one or more meal types couldn't be filled
/// (their allergen-safe pool was empty). The UI shows this without hiding the
/// meals that *were* planned.
struct WeekGenerationWarning: Equatable {
    /// Meal types ("breakfast"/"lunch"/"dinner") left entirely empty.
    let unfilledMealTypes: [String]
    /// Meals actually planned (e.g. 14 when one of three types was empty).
    let plannedMealCount: Int
    /// Meals a complete week would hold (mealTypes × 7).
    let expectedMealCount: Int

    /// A plain-language sentence for the warning banner. The meal-type names are
    /// localized display labels (the keys stay English) and joined with a
    /// locale-aware list conjunction.
    var userMessage: String {
        let names = unfilledMealTypes.map { LocalizedNames.mealType($0).lowercased() }
        let list = ListFormatter.localizedString(byJoining: names)
        return String(localized: "We couldn't find allergy-safe \(list) recipes, so those slots are empty. Adjust your allergies to fill them.")
    }
}

/// A successful generation: always a plan, plus an optional warning when the
/// week is only partially filled. `warning == nil` means a complete week.
struct WeekGenerationOutcome: Equatable {
    let plan: WeekPlan
    let warning: WeekGenerationWarning?
    /// Cuisines whose pool was too small to offer a full set of dishes for a
    /// lunch or dinner slot. Diagnostic only — a short slot is still a valid,
    /// allergen-safe, single-cuisine slot, so this never blocks or warns the
    /// user. Empty on a normal generation.
    var candidateShortfalls: [PlanGenerator.CandidateShortfall] = []
}
