//
//  GenerationState.swift
//  Meal Seek
//
//  The lifecycle of the displayed week's generation. HomeView renders the week,
//  the partial-warning banner, and the error view through this single state
//  instead of several booleans.
//

import Foundation

/// Generation is synchronous and near-instant (a local filter over the bundled
/// recipes), so `.generating` is a real but effectively zero-frame state — it
/// exists in the model, never as a spinner or artificial delay. `.idle` and
/// `.loaded` resolve their rendering from whether a plan exists for the
/// displayed week, which keeps week navigation correct without threading the
/// state through every week; `.generating` and `.failed` are explicit overrides.
enum GenerationState: Equatable {
    case idle
    case generating
    case loaded
    case failed(WeekGenerationError)
}
