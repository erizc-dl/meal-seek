//
//  RootView.swift
//  Meal Seek
//
//  Post-onboarding root: Home / Grocery / Account tabs.
//

import SwiftUI

struct RootView: View {
    let recipeStore: RecipeStore
    let preferencesStore: PreferencesStore
    let planStore: WeekPlanStore
    let groceryStateStore: GroceryStateStore
    let ratingsStore: RatingsStore
    let weekContext: WeekContext

    init(
        recipeStore: RecipeStore,
        preferencesStore: PreferencesStore,
        planStore: WeekPlanStore,
        groceryStateStore: GroceryStateStore,
        ratingsStore: RatingsStore,
        weekContext: WeekContext
    ) {
        self.recipeStore = recipeStore
        self.preferencesStore = preferencesStore
        self.planStore = planStore
        self.groceryStateStore = groceryStateStore
        self.ratingsStore = ratingsStore
        self.weekContext = weekContext
        // Built here rather than defaulted so it can persist progress through
        // the same preferences file the onboarding flag lives in.
        _walkthrough = State(initialValue: WalkthroughCoordinator(preferencesStore: preferencesStore))
        Self.configureTabBarAppearance()
    }

    @State private var selectedTab = Tab.home

    /// "Plan your first week". Lives here because the overlay must sit ABOVE the
    /// TabView -- that is what lets a step survive a tab switch and draw over
    /// whatever a tab's navigation stack has pushed.
    @State private var walkthrough: WalkthroughCoordinator

    /// Tab identity, shared with Home so the grocery nudge card can switch
    /// tabs (never push) to the Grocery list. Defined in AppTab.swift so the
    /// walkthrough can reference it without importing the view layer.
    typealias Tab = AppTab

    var body: some View {
        tabs
            // Runs once per launch, before the user can open a slot. Idempotent,
            // so a store already carrying candidate sets writes nothing.
            .task {
                planStore.migrateCandidateSets(
                    recipes: recipeStore.recipes,
                    preferences: preferencesStore.preferences
                )
            }
            .environment(\.walkthrough, walkthrough)
            // Adds nothing to the hierarchy while the walkthrough is not
            // running -- see WalkthroughOverlay.
            .walkthroughOverlay(walkthrough)
            // A tab switch is what completes a chapter handoff. Reported here
            // because this is the only place that knows a tab actually changed.
            .onChange(of: selectedTab) { _, tab in
                walkthrough.report(tabChangedTo: tab)
            }
            // The walkthrough ends deep in the Account tab (its last step runs
            // inside the recipe library), so completing it returns the user to
            // Home -- where the week they just planned is, and where the
            // completion toast lives.
            .onChange(of: walkthrough.completionCount) {
                withAnimation(.easeInOut(duration: 0.25)) { selectedTab = .home }
            }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                recipeStore: recipeStore,
                preferencesStore: preferencesStore,
                planStore: planStore,
                groceryStateStore: groceryStateStore,
                ratingsStore: ratingsStore,
                weekContext: weekContext,
                selectedTab: $selectedTab
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(Tab.home)

            GroceryView(
                recipeStore: recipeStore,
                preferencesStore: preferencesStore,
                planStore: planStore,
                groceryStateStore: groceryStateStore,
                weekContext: weekContext
            )
            .tabItem {
                Label("Grocery", systemImage: "cart.fill")
            }
            .tag(Tab.grocery)

            AccountView(
                recipeStore: recipeStore,
                preferencesStore: preferencesStore,
                planStore: planStore,
                ratingsStore: ratingsStore,
                groceryStateStore: groceryStateStore,
                weekContext: weekContext
            )
            .tabItem {
                Label("Account", systemImage: "person.crop.circle.fill")
            }
            .tag(Tab.account)
        }
        .tint(.brandOrange)
    }

    /// Tab bar per the design system: 19pt icons, 9pt labels, orange active,
    /// #ABABAB inactive, on the standard bar material.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor(Color.textTertiary)
        itemAppearance.normal.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor(Color.textTertiary),
        ]
        itemAppearance.selected.iconColor = UIColor(Color.brandOrange)
        itemAppearance.selected.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor(Color.brandOrange),
        ]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(Color.textTertiary)
    }
}
