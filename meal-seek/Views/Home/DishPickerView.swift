//
//  DishPickerView.swift
//  Meal Seek
//
//  The sheet behind "+ Add dish", "Replace", and the empty slot's "+ Add meal":
//  a multi-select browse over the whole allergen-safe library, with the slot's
//  own unselected candidates pinned above it.
//
//  Two modes, one view. `.add` multi-selects up to a budget; `.replace` picks
//  exactly one. They differ only in the counter line, the CTA, and whether a
//  second tap deselects or moves the selection — the list, the filters, and the
//  safety rules are identical, which is the point of not writing two screens.
//
//  ALLERGEN EXCLUSION IS ABSOLUTE. Every row comes from
//  `MealPickerFilter.filtered`, whose first act is `RecipeFilter.allergenSafe`.
//  There is no toggle, no parameter, and no empty-state escape hatch that
//  widens past it: when the user's profile filters the list to nothing, this
//  view explains why rather than offering anything unfiltered. Do not add one.
//

import SwiftUI

struct DishPickerView: View {
    enum Mode: Equatable {
        /// Multi-select, capped at `budget` picks this session.
        case add(budget: Int)
        /// Single-select, swapping the named dish. No budget: a 1-for-1 swap
        /// does not spend the add allowance.
        case replace(dishID: String)
    }

    let mealType: String
    let mode: Mode
    let recipes: [Recipe]
    let preferences: UserPreferences
    /// Dishes already cooked in this slot. Hidden from the list — the model
    /// refuses duplicates, so offering them would be a tap that does nothing.
    let selectedDishIDs: [String]
    /// The slot's generator candidates the user has not selected, pinned above
    /// the library under "FROM YOUR PLAN". Empty ⇒ the section is omitted.
    let planCandidateIDs: [String]
    /// Called with the chosen recipe ids, in tap order, as the sheet dismisses.
    let onConfirm: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.recipeTranslations) private var translations

    // Sheet-local by design: every presentation starts fresh.
    @State private var searchText = ""
    /// nil = every cuisine. Narrows only; never widens past the allergen filter.
    @State private var cuisineFilter: String?
    /// Starts on the slot's own meal type so a dinner slot opens showing
    /// dinners. Cleared by the chip.
    @State private var mealTypeFilter: String?
    /// Tap order, so "Add 2 recipes" appends in the order the user picked.
    @State private var selection: [String] = []

    // MARK: Mode

    private var budget: Int {
        switch mode {
        case .add(let budget): return budget
        case .replace: return 1
        }
    }

    private var isReplacing: Bool {
        if case .replace = mode { return true }
        return false
    }

    /// True once the session cap is spent: unselected rows dim and stop
    /// responding. In `.replace` the cap is 1, so picking a second row instead
    /// MOVES the selection — a single-select list that dimmed itself after one
    /// tap would strand the user with no way to change their mind.
    private var isAtCap: Bool { !isReplacing && selection.count >= budget }

    // MARK: Results

    /// Dishes to hide: what the slot already cooks, which in `.replace`
    /// includes the outgoing dish itself.
    private var hiddenIDs: Set<String> { Set(selectedDishIDs) }

    private func filtered(_ pool: [Recipe]) -> [Recipe] {
        MealPickerFilter.filtered(
            pool,
            slotMealType: mealType,
            allergens: preferences.allergens,
            cuisines: preferences.cuisines,
            searchText: searchText,
            // The picker browses the whole safe library rather than the user's
            // preferred cuisines: someone hand-picking a dish should be able to
            // reach anything they can safely eat. The cuisine chip narrows.
            allCuisines: true,
            allMealTypes: mealTypeFilter == nil,
            translations: translations,
            narrowingToCuisine: cuisineFilter
        )
    }

    /// The slot's own unselected candidates, run through the SAME filter as the
    /// library below — a search that excludes them must exclude them here too.
    private var planResults: [Recipe] {
        let candidates = planCandidateIDs.filter { !hiddenIDs.contains($0) }
        guard !candidates.isEmpty else { return [] }
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return filtered(candidates.compactMap { byID[$0] })
    }

    private var libraryResults: [Recipe] {
        let planIDs = Set(planResults.map(\.id))
        return filtered(recipes).filter { !hiddenIDs.contains($0.id) && !planIDs.contains($0.id) }
    }

    private var hasResults: Bool { !planResults.isEmpty || !libraryResults.isEmpty }

    /// True when nothing is narrowing the list but the user's allergens — the
    /// only case where the allergen empty state is the honest explanation.
    private var isUnnarrowed: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            && cuisineFilter == nil
            && mealTypeFilter == nil
    }

    private var cuisines: [String] {
        Set(recipes.map(\.cuisine)).sorted()
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
            filterRow
            counterLine

            if hasResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !planResults.isEmpty {
                            sectionHeader("FROM YOUR PLAN")
                            ForEach(planResults) { row($0) }
                            // Only worth naming the library once something sits
                            // above it; a lone header over one list is noise.
                            if !libraryResults.isEmpty {
                                sectionHeader("ALL RECIPES")
                                    .padding(.top, 10)
                            }
                        }
                        ForEach(libraryResults) { row($0) }
                    }
                    .padding(.bottom, 16)
                }
                .animation(.easeInOut(duration: 0.25), value: libraryResults.map(\.id))
            } else {
                emptyState
            }

            confirmButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    // MARK: Search

    /// 14pt to match RecipeLibraryView and MealPickerView. The design system
    /// specifies 13; all three are logged for reconciliation post-beta rather
    /// than forked here (see DESIGN_SYSTEM.md, Open Inconsistencies).
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.textTertiary)
            TextField("Search recipes", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundCard))
    }

    // MARK: Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Picker("Cuisine", selection: $cuisineFilter) {
                        Text("All cuisines").tag(String?.none)
                        ForEach(cuisines, id: \.self) { cuisine in
                            Text(LocalizedNames.cuisine(cuisine)).tag(String?.some(cuisine))
                        }
                    }
                } label: {
                    FilterChip(
                        label: cuisineFilter.map(LocalizedNames.cuisine) ?? String(localized: "Cuisine"),
                        isActive: cuisineFilter != nil
                    )
                }

                Menu {
                    Picker("Meal", selection: $mealTypeFilter) {
                        Text("All meals").tag(String?.none)
                        ForEach(PlanGenerator.mealTypes, id: \.self) { type in
                            Text(LocalizedNames.mealType(type)).tag(String?.some(type))
                        }
                    }
                } label: {
                    FilterChip(
                        label: mealTypeFilter.map(LocalizedNames.mealType) ?? String(localized: "Meal"),
                        isActive: mealTypeFilter != nil
                    )
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: Counter

    private var counterLine: some View {
        Group {
            if isReplacing {
                Text("CHOOSE 1 REPLACEMENT")
            } else {
                Text("\(selection.count) OF \(budget) SELECTED")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.textTertiary)
        .padding(.leading, 2)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(.textTertiary)
            .padding(.leading, 2)
    }

    // MARK: Row

    private func row(_ recipe: Recipe) -> some View {
        let isSelected = selection.contains(recipe.id)
        // A dimmed row is the whole feedback for a spent budget — no alert.
        let isDisabled = isAtCap && !isSelected

        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { toggle(recipe.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.brandOrange : .textTertiary)

                Text(translations.name(for: recipe))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(LocalizedNames.cuisine(recipe.cuisine)) · \(recipe.prepTimeMinutes + recipe.cookTimeMinutes)m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.textOnPale)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.brandOrangePale))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundCard)
                    .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isDisabled ? 0.4 : 1)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.25), value: isDisabled)
    }

    /// In `.replace` a tap MOVES the single selection rather than stacking one;
    /// in `.add` it toggles, and the cap is enforced by the row being disabled.
    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else if isReplacing {
            selection = [id]
        } else if selection.count < budget {
            selection.append(id)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            // Only claim allergens are the cause when nothing else is narrowing
            // the list, otherwise a plain no-match reads as an allergy problem.
            if isUnnarrowed && !preferences.allergens.isEmpty {
                Text("No recipes fit your allergies")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textSecondary)
                Text("Every recipe for this meal contains something you avoid. Adjust your allergies in Account to see more.")
                    .font(.system(size: 12))
                    .foregroundStyle(.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("No recipes match")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Confirm

    private var confirmButton: some View {
        let isEnabled = !selection.isEmpty
        return Button {
            guard isEnabled else { return }
            let ids = selection
            dismiss()
            onConfirm(ids)
        } label: {
            Group {
                if isReplacing {
                    Text("Replace")
                } else {
                    // Plural variants live in the String Catalog, matching the
                    // project's existing "%lld items left to buy" pattern.
                    Text("Add \(selection.count) recipes")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            // `.white` on a solid brandOrange fill is the design system's one
            // sanctioned use; the disabled pair matches the servings stepper.
            .foregroundStyle(isEnabled ? Color.white : .textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isEnabled ? Color.brandOrange : .backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.25), value: isEnabled)
    }
}
