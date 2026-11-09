//
//  PantrySettingsView.swift
//  Meal Seek
//
//  Account sub-screen: which ingredients are YOUR pantry staples.
//
//  What counts as "always in the cupboard" is a cuisine question, not a
//  universal one — garlic and olive oil in a Western kitchen, soy sauce and
//  sesame oil in an Eastern one. The app ships a default set; this screen lets
//  the user overrule it in either direction, and shows them exactly what they
//  changed so it is never a mystery.
//
//  A staple appears on the grocery list WITHOUT a computed quantity, under
//  "Check your pantry". That is the entire effect: it suppresses a number.
//
//  It is NOT an allergen control. Marking sesame oil as your pantry staple
//  does not make it sesame-free — allergen filtering reads `Recipe.allergens`
//  and never consults this screen. The footer says so on screen, because a
//  user could otherwise reasonably assume "my pantry" means "safe for me".
//

import SwiftUI

struct PantrySettingsView: View {
    let preferencesStore: PreferencesStore
    /// Supplies the ingredient names the user can choose from — the shipped
    /// staple set plus anything they have already marked from the grocery list.
    let recipeStore: RecipeStore

    @State private var showResetConfirmation = false

    private var overrides: [String: Bool] { preferencesStore.preferences.pantryOverrides }

    /// Names the user has genuinely changed away from the shipped default.
    private var changedNames: [String] { ShoppingListBuilder.userChangedNames(overrides) }

    /// Everything offered on this screen: the shipped staples, plus any
    /// ingredient the user marked elsewhere (from the grocery list), so a
    /// marking made there is always visible and undoable here.
    private var candidates: [String] {
        Set(ShoppingListBuilder.pantryStaples)
            .union(overrides.keys)
            .sorted()
    }

    /// Grouped by the grocery aisle each ingredient belongs to, so the list
    /// reads in the same order as the shopping list itself.
    private var grouped: [(aisle: String, names: [String])] {
        var byAisle: [String: [String]] = [:]
        // Built ONCE per evaluation. `category(of:)` used to rebuild the index
        // for every candidate — one pass over every ingredient row of every
        // recipe per staple, which at 2,352 recipes was ~160 ms of main-thread
        // work each time this screen re-rendered.
        let index = categoryIndex
        for name in candidates {
            byAisle[index[name] ?? "other", default: []].append(name)
        }
        return byAisle
            .sorted { GroceryListBuilder.aisleRank($0.key) < GroceryListBuilder.aisleRank($1.key) }
            .map { (aisle: $0.key, names: $0.value.sorted()) }
    }

    /// The ingredient's canonical grocery category, looked up from the recipe
    /// database. Falls back to "other" for a name no recipe uses.
    private func category(of name: String) -> String {
        categoryIndex[name] ?? "other"
    }

    private var categoryIndex: [String: String] {
        var index: [String: String] = [:]
        for recipe in recipeStore.recipes {
            for ingredient in recipe.ingredients where index[ingredient.name] == nil {
                index[ingredient.name] = ingredient.category
            }
        }
        return index
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                explainer
                if !changedNames.isEmpty { changedSummary }

                ForEach(grouped, id: \.aisle) { group in
                    sectionHeader(LocalizedNames.aisle(group.aisle))
                    VStack(spacing: 0) {
                        ForEach(Array(group.names.enumerated()), id: \.element) { index, name in
                            toggleRow(name)
                            if index < group.names.count - 1 { divider }
                        }
                    }
                    .background(Color.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
                }

                allergenNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Pantry staples")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: changedNames)
        .confirmationDialog(
            "Reset to the default pantry?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    preferencesStore.preferences.pantryOverrides = [:]
                    preferencesStore.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the \(changedNames.count) changes you've made and goes back to the ingredients Meal Seek treats as staples.")
        }
    }

    // MARK: Explainer

    private var explainer: some View {
        Text("Staples appear on your grocery list without an amount, under \"Check your pantry\". Turn on the ones you always have.")
            .font(.system(size: 13))
            .foregroundStyle(.textSecondary)
    }

    /// What the user changed, and the one tap that undoes all of it.
    private var changedSummary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(changedNames.count) changed by you")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textOnPale)
                Text(changedNames.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.textOnPale)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Reset") { showResetConfirmation = true }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.textOnPale)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.brandOrangePale))
    }

    // MARK: Rows

    private func toggleRow(_ name: String) -> some View {
        let isStaple = ShoppingListBuilder.isPantryStaple(name, overrides: overrides)
        return Toggle(isOn: Binding(
            get: { isStaple },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { set(name, isStaple: newValue) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(translatedName(name))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.textPrimary)
                if overrides[name] != nil,
                   overrides[name] != ShoppingListBuilder.pantryStaples.contains(name) {
                    Text("Changed by you")
                        .font(.system(size: 11))
                        .foregroundStyle(.textOnPale)
                }
            }
        }
        .tint(Color.brandOrange)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.backgroundSecondary)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.textTertiary)
            .padding(.top, 6)
            .padding(.leading, 2)
    }

    /// The one place this screen is language-aware: ingredient NAMES localize
    /// for reading. The stored key stays canonical English, exactly like the
    /// grocery list, so consolidation is untouched.
    @Environment(\.recipeTranslations) private var translations
    private func translatedName(_ name: String) -> String { translations.groceryIngredientName(name) }

    // MARK: Safety note

    private var allergenNote: some View {
        Text("Pantry staples only change whether an amount is shown. They never affect allergy filtering — a recipe containing something you're allergic to stays hidden either way.")
            .font(.system(size: 11))
            .foregroundStyle(.textTertiary)
            .padding(.top, 6)
    }

    // MARK: Persistence

    /// Records an explicit decision, or drops it when the user lands back on
    /// the shipped default — so `pantryOverrides` only ever holds real
    /// differences and "changed by you" cannot drift out of sync.
    private func set(_ name: String, isStaple: Bool) {
        var updated = preferencesStore.preferences.pantryOverrides
        if isStaple == ShoppingListBuilder.pantryStaples.contains(name) {
            updated.removeValue(forKey: name)
        } else {
            updated[name] = isStaple
        }
        preferencesStore.preferences.pantryOverrides = updated
        preferencesStore.save()
    }
}
