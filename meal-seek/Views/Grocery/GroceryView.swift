//
//  GroceryView.swift
//  Meal Seek
//
//  The shopping list for the week currently displayed on Home: derived from
//  that week's plan, grouped by aisle, with a persistent, collapsible Bought
//  section. The only mutations are check/uncheck — the list itself is derived.
//

import SwiftUI

struct GroceryView: View {
    let recipeStore: RecipeStore
    let preferencesStore: PreferencesStore
    let planStore: WeekPlanStore
    let groceryStateStore: GroceryStateStore
    let weekContext: WeekContext
    /// Display-layer localization of item names and unit labels. Consolidation
    /// (ids, dedup, quantities, aisles) stays entirely on canonical English —
    /// the store never reaches GroceryListBuilder.
    @Environment(\.recipeTranslations) private var translations

    @Environment(\.walkthrough) private var walkthrough

    @State private var searchText = ""
    @State private var isBoughtCollapsed = false
    @State private var showClearAlert = false
    @Namespace private var rowNamespace

    private var weekStart: Date { weekContext.displayedWeekStart }

    /// The full derived list for the displayed week (unfiltered by search).
    /// Built through the shopping layer, so quantities read like a shopping list
    /// (grams/ml, pantry staples de-quantified) rather than cooking units.
    private var allItems: [GroceryItem] {
        guard let plan = planStore.plan(for: weekStart) else { return [] }
        return ShoppingListBuilder.build(
            plan: plan,
            recipes: recipeStore.recipes,
            householdSize: preferencesStore.preferences.householdSize,
            pantryOverrides: preferencesStore.preferences.pantryOverrides
        )
    }

    /// Bought row IDs — the bare name, or "name#family" for split rows.
    /// Only ever compared against `item.id`; never displayed or searched.
    private var boughtIDs: Set<String> {
        groceryStateStore.boughtNames(for: weekStart)
    }

    private func matchesSearch(_ item: GroceryItem) -> Bool {
        searchText.isEmpty
            || item.name.localizedCaseInsensitiveContains(searchText)
            || translations.groceryIngredientName(item.name).localizedCaseInsensitiveContains(searchText)
    }

    private var visibleUnbought: [GroceryItem] {
        allItems.filter { !boughtIDs.contains($0.id) && matchesSearch($0) }
    }

    private var visibleBought: [GroceryItem] {
        allItems.filter { boughtIDs.contains($0.id) && matchesSearch($0) }
    }

    /// Aisles present in the unbought list, already in shopping order because
    /// the builder sorts items that way. Pantry staples are excluded — they get
    /// their own "Check your pantry" section, not an aisle.
    private var visibleAisles: [String] {
        var seen = Set<String>()
        return visibleUnbought
            .filter { !$0.isPantryStaple }
            .compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    /// The row "Plan your first week" points at for its check-off step: the
    /// very first unbought item in shopping order. Nil once nothing is left to
    /// buy, in which case the overlay hides itself rather than pointing at a
    /// row that is no longer there.
    private var spotlightItemID: String? {
        visibleUnbought.first { !$0.isPantryStaple }?.id ?? visibleUnbought.first?.id
    }

    /// Unbought pantry staples for the displayed week (salt, oils, dried spices).
    private var visiblePantryStaples: [GroceryItem] {
        visibleUnbought.filter(\.isPantryStaple)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if planStore.plan(for: weekStart) == nil {
                    emptyState
                } else {
                    searchField
                    progressCard
                    aisleSections
                    pantrySection
                    boughtSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .spotlightScreen()
        // Bring the step's target into view BEFORE its cutout is drawn. The
        // Bought header sits at the bottom of a list that can run to 60 items,
        // so on a real week it is always below the fold when step 6 begins.
        .onChange(of: walkthrough.isPreparing) { _, preparing in
            guard preparing, let step = walkthrough.step else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                switch step {
                case .checkOff: scrollProxy.scrollTo(spotlightItemID, anchor: .center)
                case .unCheck: scrollProxy.scrollTo(Self.boughtHeaderID, anchor: .center)
                default: break
                }
            }
        }
        .onAppear(perform: reconcileBoughtState)
        .onChange(of: allItems.map(\.id), reconcileBoughtState)
        .alert("Clear bought items?", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear") { clearBought() }
        } message: {
            Text("All items will return to their aisles.")
        }
        }
    }

    /// Scroll identity for the Bought header. A constant rather than the step
    /// itself so the header keeps one identity across steps.
    private static let boughtHeaderID = "walkthrough.boughtHeader"

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Grocery list")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.textPrimary)
            Text("Week of \(weekStart.formatted(.dateTime.month(.wide).day()))")
                .font(.system(size: 11))
                .foregroundStyle(.textTertiary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.textTertiary)
            TextField("Search items", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundCard))
    }

    // MARK: Progress

    private var progressCard: some View {
        let total = allItems.count
        let bought = allItems.count { boughtIDs.contains($0.id) }
        let fraction = total > 0 ? Double(bought) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bought.formatted())
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.brandOrange)
                Text("of \(total) in cart")
                    .font(.system(size: 13))
                    .foregroundStyle(.textSecondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "#EFEFEF"))
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.brandOrange)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(.easeInOut(duration: 0.25), value: fraction)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: Aisle sections

    private var aisleSections: some View {
        ForEach(visibleAisles, id: \.self) { aisle in
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedNames.aisle(aisle).uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.textOnPale)
                    .padding(.top, 6)

                ForEach(visibleUnbought.filter { $0.category == aisle && !$0.isPantryStaple }) { item in
                    groceryRow(item, bought: false)
                        .matchedGeometryEffect(id: item.id, in: rowNamespace)
                        // The whole ROW is the tap target; the CUTOUT is drawn
                        // tight around the checkbox by `spotlightCutout` inside
                        // the row. Two rects, one general mechanism -- this used
                        // to be a hand-correction in the engine.
                        .spotlightTarget(item.id == spotlightItemID ? .checkOff : nil, cornerRadius: 12)
                }
            }
        }
    }

    // MARK: Pantry staples

    /// Salt, oils, dried spices — the week needs them, but a summed quantity is
    /// nonsense, so they show under their own header without one. Same row and
    /// header treatment as an aisle (per DESIGN_SYSTEM.md), so they still check
    /// off and fly to Bought like any other item.
    @ViewBuilder private var pantrySection: some View {
        if !visiblePantryStaples.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("grocery.checkPantry", value: "Check your pantry",
                                       comment: "Header for the pantry-staples section of the grocery list").uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.textOnPale)
                    .padding(.top, 6)

                ForEach(visiblePantryStaples) { item in
                    groceryRow(item, bought: false)
                        .matchedGeometryEffect(id: item.id, in: rowNamespace)
                }
            }
        }
    }

    // MARK: Bought section

    private var boughtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isBoughtCollapsed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isBoughtCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("BOUGHT · \(visibleBought.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    // textSecondary across the WHOLE label, not textTertiary and
                    // not a split. This is a real Button, and tertiary is the
                    // token for captions, inactive and disabled -- at 2.30:1 it
                    // also sits under WCAG 2.2's 3:1 floor for non-text UI.
                    //
                    // It still reads as a section header: 11pt medium UPPERCASE
                    // is what carries header semantics here, not the color. And
                    // this screen's other headers (PRODUCE, DAIRY & EGGS, CHECK
                    // YOUR PANTRY) are textOnPale, so this row never matched
                    // them anyway -- darkening moves it closer to their weight,
                    // not further away.
                    .foregroundStyle(.textSecondary)
                }
                .buttonStyle(PressableButtonStyle())
                .spotlightTarget(.unCheck, cornerRadius: 8)
                .id(Self.boughtHeaderID)

                Spacer()

                if !visibleBought.isEmpty {
                    Button("Clear") { showClearAlert = true }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.brandOrange)
                        .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.top, 10)

            if !isBoughtCollapsed {
                ForEach(visibleBought) { item in
                    groceryRow(item, bought: true)
                        .matchedGeometryEffect(id: item.id, in: rowNamespace)
                }
            }
        }
    }

    // MARK: Rows

    private func groceryRow(_ item: GroceryItem, bought: Bool) -> some View {
        Button {
            setBought(item, to: !bought)
            // Reports what the user just did. The coordinator ignores it unless
            // it happens to be the step in progress.
            walkthrough.report(bought ? .itemUnbought : .itemBought)
        } label: {
            HStack(spacing: 12) {
                checkbox(checked: bought)
                    .spotlightCutout(
                        (!bought && item.id == spotlightItemID) ? .checkOff : nil,
                        cornerRadius: 11
                    )

                Text(translations.groceryIngredientName(item.name).capitalized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(bought ? .textTertiary : .textPrimary)
                    .strikethrough(bought, color: .textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let quantity = translations.groceryQuantity(item) {
                    Text(quantity)
                        .font(.system(size: 13))
                        .foregroundStyle(bought ? .textTertiary : .textSecondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bought ? Color.backgroundSecondary : .backgroundCard)
                    .shadow(color: .black.opacity(bought ? 0 : 0.03), radius: 6, y: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        // Marking pantry from the list itself, since that is where a user
        // notices "I always have this". A long-press menu rather than a swipe:
        // the row's tap already means bought, and a destructive-looking swipe
        // would read as delete. The label always states which way it goes, so
        // it can never happen silently, and it is reversible from the same menu
        // or from Account ▸ Pantry staples.
        .contextMenu {
            let isStaple = ShoppingListBuilder.isPantryStaple(
                item.name, overrides: preferencesStore.preferences.pantryOverrides
            )
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    setPantry(item.name, isStaple: !isStaple)
                }
            } label: {
                Label(
                    isStaple
                        ? String(localized: "Remove from pantry staples")
                        : String(localized: "I always have this"),
                    systemImage: isStaple ? "cabinet" : "cabinet.fill"
                )
            }
        }
    }

    /// Records the user's pantry decision, dropping the entry when it lands
    /// back on the shipped default so `pantryOverrides` only holds genuine
    /// differences. Quantity-only: allergen filtering reads `Recipe` and is
    /// untouched by anything here.
    private func setPantry(_ name: String, isStaple: Bool) {
        var updated = preferencesStore.preferences.pantryOverrides
        if isStaple == ShoppingListBuilder.pantryStaples.contains(name) {
            updated.removeValue(forKey: name)
        } else {
            updated[name] = isStaple
        }
        preferencesStore.preferences.pantryOverrides = updated
        preferencesStore.save()
    }

    private func checkbox(checked: Bool) -> some View {
        ZStack {
            Circle()
                .fill(checked ? Color.brandOrange : .clear)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(Color(hex: "#D4D4D4"), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: Empty state

    private var emptyState: some View {
        Text("No plan for this week yet")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 180)
    }

    // MARK: Actions

    private func setBought(_ item: GroceryItem, to bought: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            groceryStateStore.setBought(item.id, bought: bought, for: weekStart)
        }
    }

    private func clearBought() {
        withAnimation(.easeInOut(duration: 0.3)) {
            groceryStateStore.clear(for: weekStart)
        }
    }

    /// Drops checked row IDs that no longer appear in the derived list (e.g.
    /// after the week was regenerated on Home). Preserves everything else.
    private func reconcileBoughtState() {
        guard planStore.plan(for: weekStart) != nil else { return }
        groceryStateStore.retainOnly(names: Set(allItems.map(\.id)), for: weekStart)
    }

}
