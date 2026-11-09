//
//  AllergiesSettingsView.swift
//  Meal Seek
//
//  Account sub-screen: edit allergens with the same capsule chips as
//  onboarding. ADDING an allergen is a safety rule: unsafe meals are removed
//  from the current and future weeks immediately, no prompt, and the user is
//  told what happened. REMOVING one only ever means a regeneration OFFER —
//  made once, on the way out, and only if the visit actually changed
//  something. AccountView presents that prompt, because this screen is
//  already popped when it fires.
//

import SwiftUI

struct AllergiesSettingsView: View {
    let recipeStore: RecipeStore
    let preferencesStore: PreferencesStore
    let planStore: WeekPlanStore
    let weekContext: WeekContext
    /// Called on exit when the visit changed the plan's inputs: the allergen
    /// set differs from entry, or safety enforcement stripped meals (which
    /// leaves the plan changed even if the selection was toggled back).
    let onExitWithChanges: () -> Void

    /// The selection as it was when the screen appeared.
    @State private var entryAllergens: Set<String>?
    /// True once safety enforcement removed meals during this visit.
    @State private var safetyRemovedMeals = false
    @State private var removalMessage: String?

    /// (stored snake_case value that matches the JSON, human-readable label).
    private let allergens: [(value: String, label: String)] = [
        ("gluten", "Gluten"),
        ("dairy", "Dairy"),
        ("egg", "Egg"),
        ("soy", "Soy"),
        ("peanut", "Peanut"),
        ("tree_nut", "Tree nut"),
        ("shellfish", "Shellfish"),
        ("fish", "Fish"),
        ("sesame", "Sesame"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlowLayout(spacing: 10) {
                    ForEach(allergens, id: \.value) { allergen in
                        SelectableChip(
                            label: LocalizedNames.allergen(allergen.value),
                            isSelected: preferencesStore.preferences.allergens.contains(allergen.value),
                            action: { toggle(allergen) }
                        )
                    }
                }

                Text("Best-effort filtering, not a medical guarantee. Always check labels.")
                    .font(.system(size: 11))
                    .foregroundStyle(.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Allergies")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entryAllergens == nil {
                entryAllergens = preferencesStore.preferences.allergens
            }
        }
        .onDisappear(perform: offerRegenerationIfChanged)
        .alert(
            "Plan updated",
            isPresented: Binding(
                get: { removalMessage != nil },
                set: { if !$0 { removalMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalMessage ?? "")
        }
    }

    /// Saves on every toggle; adding still enforces safety immediately. Only
    /// the regeneration OFFER is deferred to exit.
    private func toggle(_ allergen: (value: String, label: String)) {
        var selected = preferencesStore.preferences.allergens
        if selected.contains(allergen.value) {
            selected.remove(allergen.value)
            preferencesStore.preferences.allergens = selected
            preferencesStore.save()
            // Removal makes nothing unsafe — the exit offer covers it.
        } else {
            selected.insert(allergen.value)
            preferencesStore.preferences.allergens = selected
            preferencesStore.save()
            enforceAllergenSafety(allergen)
        }
    }

    /// The safety rule: strip meals containing the new allergen from the
    /// current and all future weeks, immediately and without asking. Past
    /// weeks are historical and stay untouched. Then tell the user.
    private func enforceAllergenSafety(_ allergen: (value: String, label: String)) {
        let currentWeekStart = Calendar.current.mondayOfWeek(containing: Date())
        let result = PlanEditor.removingMeals(
            containingAllergen: allergen.value,
            fromPlans: Array(planStore.plans.values),
            recipes: recipeStore.recipes,
            currentWeekStart: currentWeekStart
        )
        guard result.removedMealCount > 0 else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            for plan in result.updatedPlans {
                planStore.save(plan)
            }
        }
        safetyRemovedMeals = true
        removalMessage = String(localized: "Removed \(result.removedMealCount) meals containing \(LocalizedNames.allergen(allergen.value).lowercased()).")
    }

    /// One offer per visit, on the way out. Toggle-and-revert makes no offer
    /// unless safety enforcement already emptied slots (then regeneration is
    /// how the user refills them). Only when there is a plan the change could
    /// apply to, and never for a past (read-only) week.
    private func offerRegenerationIfChanged() {
        guard let entryAllergens else { return }
        guard preferencesStore.preferences.allergens != entryAllergens || safetyRemovedMeals else { return }
        let currentWeekStart = Calendar.current.mondayOfWeek(containing: Date())
        guard weekContext.displayedWeekStart >= currentWeekStart,
              planStore.hasPlan(for: weekContext.displayedWeekStart) else { return }
        onExitWithChanges()
    }
}
