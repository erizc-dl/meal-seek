//
//  MealSeekApp.swift
//  Meal Seek
//
//  Created by Eric Zhang on 10/17/26.
//

import SwiftUI

@main
struct MealSeekApp: App {
    @State private var recipeStore: RecipeStore
    @State private var preferencesStore: PreferencesStore
    @State private var planStore = WeekPlanStore()
    @State private var groceryStateStore = GroceryStateStore()
    @State private var ratingsStore = RatingsStore()
    @State private var weekContext = WeekContext()
    /// Display-layer recipe translations for the active app language (loads
    /// lazily on first lookup; nothing loads when the app is in English).
    private let translationStore = RecipeTranslationStore()
    #if DEBUG
    /// The 🧪 generator test lab (debug builds only).
    @State private var showsLab = false
    #endif

    init() {
        // RecipeStore owns the user-recipe store and merges the two pools, so
        // every downstream consumer sees one array of recipes.
        let recipeStore = RecipeStore()
        let preferencesStore = PreferencesStore()
        // Upgrade pre-cuisine preference files before any view reads them.
        preferencesStore.migrateRegionsToCuisines(using: recipeStore.catalog)
        _recipeStore = State(initialValue: recipeStore)
        _preferencesStore = State(initialValue: preferencesStore)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if preferencesStore.preferences.hasCompletedOnboarding {
                    RootView(
                        recipeStore: recipeStore,
                        preferencesStore: preferencesStore,
                        planStore: planStore,
                        groceryStateStore: groceryStateStore,
                        ratingsStore: ratingsStore,
                        weekContext: weekContext
                    )
                } else {
                    OnboardingView(store: preferencesStore, recipeStore: recipeStore, onComplete: planCurrentWeek)
                }
            }
            #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                Button { showsLab = true } label: {
                    Text("🧪").font(.title2).padding(10).background(.thinMaterial, in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.bottom, 90)
                .accessibilityLabel("Generator test lab")
            }
            .sheet(isPresented: $showsLab) {
                GeneratorLabView(recipeStore: recipeStore)
            }
            #endif
            .environment(\.recipeTranslations, translationStore)
            // Recipe amounts follow the servings set in Account, the same
            // householdSize the grocery list already scales by.
            .environment(\.cookingServings, preferencesStore.preferences.householdSize)
        }
    }

    /// Runs once when the user finishes onboarding ("Build my week") — the one
    /// generation that isn't triggered from the Home screen. Saved plans are
    /// otherwise only loaded, never regenerated, on launch.
    private func planCurrentWeek() {
        let weekStart = Calendar.current.mondayOfWeek(containing: Date())
        let outcome = PlanGenerator.generate(
            recipes: recipeStore.recipes,
            preferences: preferencesStore.preferences,
            ratings: ratingsStore.ratings,
            weekStartDate: weekStart,
            databaseLoadFailureReason: recipeStore.loadFailureReason
        )
        // A partial week is still saved (its warning is surfaced on Home). On a
        // hard failure, leave the week unplanned: Home shows its unplanned
        // state, and the user's "Plan this week" tap there surfaces the
        // designed error screen with a report action.
        if case .success(let success) = outcome {
            planStore.save(success.plan)
        }
    }
}
