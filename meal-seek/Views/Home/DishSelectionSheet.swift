//
//  DishSelectionSheet.swift
//  Meal Seek
//
//  The sheet behind a lunch or dinner card: the slot's same-cuisine candidates,
//  with a checkable row each, and one Confirm that writes the whole selection
//  back at once.
//
//  Selection is edited in sheet-local state and only committed on Confirm, so
//  backing out costs nothing and the grocery list never churns mid-edit. An
//  empty selection is representable HERE (the user can untick everything) but
//  cannot be committed — Confirm disables — because an empty slot is a data
//  state the plan does not have.
//
//  Every row shown is a candidate the generator already filtered: allergen
//  exclusion happened before this view existed and is not re-checked here,
//  because there is nothing here that could add a recipe to the set.
//

import SwiftUI

struct DishSelectionSheet: View {
    let mealType: String
    /// The slot's candidates, in draw order, already resolved to recipes.
    let candidates: [Recipe]
    /// Recipe ids selected when the sheet opened.
    let initialSelection: [String]
    let ratingsStore: RatingsStore
    /// Called with the confirmed ids as the sheet dismisses. Never empty.
    let onConfirm: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.recipeTranslations) private var translations

    @State private var selection: Set<String> = []
    /// Non-nil while a recipe detail is pushed from a row's chevron. Held as an
    /// id because `Recipe` is Identifiable but not Hashable.
    @State private var detailRecipeID: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(candidates) { recipe in
                            row(recipe)
                        }
                    }
                    .padding(.bottom, 16)
                }

                confirmButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .presentationDragIndicator(.visible)
            .navigationDestination(item: $detailRecipeID) { id in
                if let recipe = candidates.first(where: { $0.id == id }) {
                    RecipeDetailView(recipe: recipe, ratingsStore: ratingsStore)
                }
            }
        }
        .onAppear { selection = Set(initialSelection) }
    }

    /// Per-meal-type keys rather than an interpolated noun, so each language
    /// can phrase the whole sentence naturally.
    private var title: String {
        mealType == "lunch"
            ? String(localized: "Choose your lunch")
            : String(localized: "Choose your dinner")
    }

    // MARK: Rows

    private func row(_ recipe: Recipe) -> some View {
        let isSelected = selection.contains(recipe.id)
        return HStack(spacing: 12) {
            // The row body toggles; the chevron opens the recipe. Two targets,
            // so reading about a dish never silently changes what gets cooked.
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { toggle(recipe.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.brandOrange : .textTertiary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(translations.name(for: recipe))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text("\(LocalizedNames.cuisine(recipe.cuisine)) · \(recipe.prepTimeMinutes + recipe.cookTimeMinutes)m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.textOnPale)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.brandOrangePale))
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                detailRecipeID = recipe.id
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("View recipe"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.brandOrangePale : .backgroundCard)
        )
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    // MARK: Confirm

    /// Committed in candidate order, not tap order, so the slot's headline dish
    /// stays stable when the user ticks extras.
    private var confirmedIDs: [String] {
        candidates.map(\.id).filter { selection.contains($0) }
    }

    private var confirmButton: some View {
        let count = confirmedIDs.count
        let isEnabled = count > 0
        return Button {
            guard isEnabled else { return }
            let ids = confirmedIDs
            dismiss()
            onConfirm(ids)
        } label: {
            // Plural variants live in the String Catalog, matching the
            // project's existing "%lld items left to buy" pattern.
            Text("Confirm · \(count) dishes")
                .font(.system(size: 17, weight: .semibold))
                // `.white` on a solid brandOrange fill is the design system's
                // one sanctioned use; the disabled pair matches the servings
                // stepper's disabled −.
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
