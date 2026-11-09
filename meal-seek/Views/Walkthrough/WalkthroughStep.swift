//
//  WalkthroughStep.swift
//  Meal Seek
//
//  The eight steps of "Plan your first week", and what each one points at.
//
//  NAMING: this feature is called "Plan your first week", never "Tutorial", in
//  every user-facing string AND every symbol name. The milestone brief sketched
//  these types as `TutorialCoordinator` / `TutorialOverlay` / `TutorialStep` in
//  one section and forbade the word "Tutorial" in symbol names in the next; the
//  prohibition is the more specific instruction, so the types are `Walkthrough*`.
//
//  EVERY STEP IS COMPLETED BY THE USER DOING THE REAL THING. There is no
//  simulated tap, no sample plan, no "watch this". Each `advancesOn` names a
//  real state change in the user's real data, and the step does not move until
//  that change actually happens.
//

import SwiftUI

enum WalkthroughStep: String, CaseIterable, Identifiable, Codable {
    // Chapter 1 — Home
    case seeWeek
    case reshuffle
    case swapDish
    case removeDish
    // Chapter 2 — Grocery
    case checkOff
    case unCheck
    // Chapter 3 — Account
    case recipeLibrary
    case openRecipe
    case ratings

    var id: String { rawValue }

    /// Position in the run, for the progress dots.
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static var count: Int { allCases.count }

    var next: WalkthroughStep? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    // MARK: What advances it

    /// The real state change that completes a step.
    ///
    /// `.userConfirms` is the ONLY non-action gate, and it is used exactly twice
    /// -- for the two teaching beats that have nothing to do (Remove works like
    /// Replace; ratings teach the planner). Everywhere else the user performs
    /// the actual interaction on their actual plan.
    enum Gate {
        /// A different day is selected on Home.
        case dayChanged
        /// The displayed week was regenerated.
        case weekRegenerated
        /// A slot's selected dishes changed.
        case dishSelectionChanged
        /// An unbought grocery item became bought.
        case itemBought
        /// A bought grocery item went back to the list.
        case itemUnbought
        /// The recipe library actually appeared.
        case openedRecipeLibrary
        /// A recipe's detail screen actually appeared.
        case openedRecipeDetail
        /// Nothing to do -- the card carries a "Next".
        case userConfirms
    }

    var advancesOn: Gate {
        switch self {
        case .seeWeek: return .dayChanged
        case .reshuffle: return .weekRegenerated
        case .swapDish: return .dishSelectionChanged
        case .removeDish: return .userConfirms
        case .checkOff: return .itemBought
        case .unCheck: return .itemUnbought
        case .recipeLibrary: return .openedRecipeLibrary
        case .openRecipe: return .openedRecipeDetail
        case .ratings: return .userConfirms
        }
    }

    /// True when the coach card shows a "Next" button.
    var isNonAction: Bool { advancesOn == .userConfirms }

    /// A step whose gate can strand the user offers Next after this long.
    ///
    /// Only `unCheck` has one. Un-checking an item is genuinely optional -- a
    /// user who does not want to put anything back must not be stuck behind a
    /// gate they have no reason to satisfy.
    var fallbackNextAfter: Duration? {
        self == .unCheck ? .seconds(5) : nil
    }

    // MARK: What it points at

    /// After its gate fires, a step may hand off to a tab item before advancing:
    /// the spotlight moves to the tab, and the real advance waits for the user to
    /// actually switch tabs.
    ///
    /// This is what carries the user between chapters without a "go to the
    /// Grocery tab now" step of its own.
    var handoff: AppTab? {
        switch self {
        case .removeDish: return .grocery
        case .unCheck: return .account
        default: return nil
        }
    }

    /// Which tab item to spotlight while handing off. Tab items are the ONE
    /// target that cannot publish an anchor -- `.tabItem` labels are consumed as
    /// configuration and rendered by UIKit, never entering the SwiftUI layout
    /// tree -- so the overlay derives their rect instead. See TabBarGeometry.
    var handoffTabIndex: Int? {
        guard let handoff else { return nil }
        return AppTab.allCases.firstIndex(of: handoff)
    }

    /// Steps whose target lives inside a scroll view and may be out of sight
    /// when the step begins -- the Bought header at the bottom of a 60-item
    /// list, a recipe row below the fold.
    var needsScrollIntoView: Bool {
        switch self {
        case .checkOff, .unCheck, .openRecipe: return true
        default: return false
        }
    }

    /// Steps that point at nothing: the card stands alone over the scrim.
    var hasNoSpotlight: Bool {
        switch self {
        case .removeDish: return true
        default: return false
        }
    }

    // MARK: Copy

    var title: LocalizedStringKey {
        switch self {
        case .seeWeek: return "Your week's already planned"
        case .reshuffle: return "Not feeling this week?"
        case .swapDish: return "Every dish can be swapped"
        case .removeDish: return "Removing works the same way"
        case .checkOff: return "Tick things off as you shop"
        case .unCheck: return "Changed your mind?"
        case .recipeLibrary: return "All your recipes live here"
        case .openRecipe: return "Open any recipe"
        case .ratings: return "Tell Meal Seek what you liked"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .seeWeek:
            return "Built around the cuisines you picked, minus anything you're allergic to. Tap any day to look around."
        case .reshuffle:
            return "This button gives you a brand-new week."
        case .swapDish:
            return "Tap the three dots beside any dish. A menu opens with Replace and Remove."
        case .removeDish:
            return "Same menu, one tap down. Now let's look at what you need to buy."
        case .checkOff:
            return "Tap an item to move it into your cart."
        case .unCheck:
            return "Tap it again to put it back on the list."
        case .recipeLibrary:
            return "Browse everything Meal Seek knows, and add your own."
        case .openRecipe:
            return "Tap any recipe to see how it's made."
        case .ratings:
            return "Thumbs up or down teaches Meal Seek what to plan next. You don't have to rate anything now."
        }
    }

    /// Replaces `message` while the step is handing off to a tab.
    var handoffMessage: LocalizedStringKey? {
        switch self {
        case .removeDish: return "Open your grocery list to keep going."
        case .unCheck: return "Last stop — open your account."
        default: return nil
        }
    }
}
