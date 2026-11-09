//
//  CuisinesSettingsView.swift
//  Meal Seek
//
//  Account sub-screen: edit cuisine selection with the same expandable region
//  cards as onboarding. Saves on every change; cuisine changes are never
//  unsafe, so the user is asked whether to regenerate rather than having it
//  done to them — once, on the way out, and only if the selection actually
//  changed from what it was on entry. AccountView presents that prompt,
//  because this screen is already popped when it fires.
//

import SwiftUI

struct CuisinesSettingsView: View {
    let preferencesStore: PreferencesStore
    let planStore: WeekPlanStore
    let weekContext: WeekContext
    /// The derived region → cuisine catalog for the picker.
    let catalog: CuisineCatalog
    /// Called on exit when the selection differs from entry and the displayed
    /// week could be regenerated to match.
    let onExitWithChanges: () -> Void

    /// The selection as it was when the screen appeared.
    @State private var entryCuisines: Set<String>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RegionCuisinePicker(catalog: catalog, selection: cuisineSelection)

                Text("At least one cuisine stays selected.")
                    .font(.system(size: 11))
                    .foregroundStyle(.textTertiary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Cuisines")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entryCuisines == nil {
                entryCuisines = preferencesStore.preferences.cuisines
            }
        }
        .onDisappear(perform: offerRegenerationIfChanged)
    }

    /// Saves on every change. Only the regeneration OFFER is deferred to
    /// exit — never the saving. The picker itself guards against emptying
    /// the selection.
    private var cuisineSelection: Binding<Set<String>> {
        Binding(
            get: { preferencesStore.preferences.cuisines },
            set: { newValue in
                guard newValue != preferencesStore.preferences.cuisines else { return }
                preferencesStore.preferences.cuisines = newValue
                preferencesStore.save()
            }
        )
    }

    /// One offer per visit, on the way out: only if the selection ended up
    /// different from entry (toggle-and-revert makes no offer), only when
    /// there is a plan the change could apply to, and never for a past
    /// (read-only) week.
    private func offerRegenerationIfChanged() {
        guard let entryCuisines,
              preferencesStore.preferences.cuisines != entryCuisines else { return }
        let currentWeekStart = Calendar.current.mondayOfWeek(containing: Date())
        guard weekContext.displayedWeekStart >= currentWeekStart,
              planStore.hasPlan(for: weekContext.displayedWeekStart) else { return }
        onExitWithChanges()
    }
}
