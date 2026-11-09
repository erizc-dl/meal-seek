//
//  UserPreferences.swift
//  Meal Seek
//
//  The user's onboarding choices, persisted as JSON in the Documents directory.
//

import Foundation

struct UserPreferences: Codable, Equatable {
    /// Selected cuisines (e.g. "Italian"), the unit of preference since the
    /// 17-cuisine database. Empty only before onboarding or migration.
    var cuisines: Set<String>
    /// Legacy region-level selection from pre-cuisine builds. Kept so old
    /// preference files migrate (each region expands to all its cuisines);
    /// nothing consults it after migration.
    var regions: Set<String>
    /// Selected allergens to avoid, stored as the exact snake_case JSON values
    /// (e.g. "tree_nut"), from the 9 supported allergens.
    var allergens: Set<String>
    /// Household size, minimum 1.
    var householdSize: Int
    var hasCompletedOnboarding: Bool
    /// Cosmetic, local-only display name shown on the Account screen. There is
    /// no account system behind it.
    var displayName: String
    /// The user's own pantry decisions, layered OVER
    /// `ShoppingListBuilder.pantryStaples`. Only ingredients the user has
    /// explicitly decided about appear here: `true` = "I always have this,
    /// don't compute an amount", `false` = "no, put it on my list with a
    /// quantity". Anything absent keeps the shipped default, so a user who
    /// never opens the screen still gets sensible behaviour and one who does
    /// is never starting from nothing.
    ///
    /// Storing only explicit decisions (rather than a full copy of the staple
    /// set) is what lets the shipped defaults evolve: adding a staple in a
    /// later release reaches every user who never had an opinion about it.
    ///
    /// GROCERY-DISPLAY ONLY. This suppresses a computed quantity; it never
    /// reaches allergen filtering, which reads `Recipe.allergens`. Marking
    /// sesame oil as your pantry staple does not make it sesame-free.
    var pantryOverrides: [String: Bool]

    /// "Plan your first week" state.
    ///
    /// Lives here, on the same struct as `hasCompletedOnboarding`, because that
    /// is the app's existing first-run precedent -- a JSON file in Documents,
    /// not UserDefaults. It also means these ride along in backup and restore
    /// automatically, since `BackupArchive` stores the whole struct. Matching
    /// the precedent rather than inventing a second one.
    var hasCompletedWalkthrough: Bool
    /// How far an interrupted run got, so it can resume where it left off.
    /// Nil once complete, or before it has ever started.
    ///
    /// Held as the step's RAW STRING, not as `WalkthroughStep`. The walkthrough
    /// lives in the view layer, and this struct is compiled by the pure-logic
    /// test harnesses, which do not build `Views/`. A string also gives the
    /// forward-compatibility we want for free: a step renamed in a later build
    /// simply fails to resolve and restarts the run.
    var walkthroughLastStep: String?
    /// Set when the user dismisses the Home invitation card. It never comes
    /// back; the Account row becomes the only route in.
    var hasDismissedWalkthroughInvitation: Bool

    init(
        cuisines: Set<String> = [],
        regions: Set<String> = [],
        allergens: Set<String> = [],
        householdSize: Int = 4,
        hasCompletedOnboarding: Bool = false,
        displayName: String = "Your kitchen",
        pantryOverrides: [String: Bool] = [:],
        hasCompletedWalkthrough: Bool = false,
        walkthroughLastStep: String? = nil,
        hasDismissedWalkthroughInvitation: Bool = false
    ) {
        self.cuisines = cuisines
        self.regions = regions
        self.allergens = allergens
        self.householdSize = max(1, householdSize)
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.displayName = displayName
        self.pantryOverrides = pantryOverrides
        self.hasCompletedWalkthrough = hasCompletedWalkthrough
        self.walkthroughLastStep = walkthroughLastStep
        self.hasDismissedWalkthroughInvitation = hasDismissedWalkthroughInvitation
    }

    // Tolerant decoding: any missing key falls back to its default so an older
    // or partial preferences file never fails to load. householdSize is clamped
    // to a minimum of 1. A pre-cuisine file decodes with empty `cuisines`,
    // which PreferencesStore.migrateRegionsToCuisines then fills.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cuisines = try container.decodeIfPresent(Set<String>.self, forKey: .cuisines) ?? []
        let regions = try container.decodeIfPresent(Set<String>.self, forKey: .regions) ?? []
        let allergens = try container.decodeIfPresent(Set<String>.self, forKey: .allergens) ?? []
        let householdSize = try container.decodeIfPresent(Int.self, forKey: .householdSize) ?? 4
        let hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Your kitchen"
        // Absent in every file written before the pantry screen existed, and in
        // any backup made then — those users simply keep the shipped defaults.
        let pantryOverrides = try container.decodeIfPresent([String: Bool].self, forKey: .pantryOverrides) ?? [:]
        // Absent in every file written before the walkthrough shipped, and in
        // any backup made then -- those users get the walkthrough offered once,
        // which is the correct outcome for an existing user who has never seen
        // it. An unrecognised step string (a renamed case in a later build)
        // decodes as nil and simply restarts the run rather than failing the
        // whole preferences file.
        let hasCompletedWalkthrough = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedWalkthrough) ?? false
        let walkthroughLastStep = try container.decodeIfPresent(String.self, forKey: .walkthroughLastStep)
        let hasDismissedWalkthroughInvitation = try container.decodeIfPresent(Bool.self, forKey: .hasDismissedWalkthroughInvitation) ?? false
        self.init(
            cuisines: cuisines,
            regions: regions,
            allergens: allergens,
            householdSize: householdSize,
            hasCompletedOnboarding: hasCompletedOnboarding,
            displayName: displayName,
            pantryOverrides: pantryOverrides,
            hasCompletedWalkthrough: hasCompletedWalkthrough,
            walkthroughLastStep: walkthroughLastStep,
            hasDismissedWalkthroughInvitation: hasDismissedWalkthroughInvitation
        )
    }
}
