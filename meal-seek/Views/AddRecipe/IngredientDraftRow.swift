//
//  IngredientDraftRow.swift
//  Meal Seek
//
//  One editable ingredient inside AddRecipeView: name (with canonical
//  suggestions), quantity, unit, and preparation.
//
//  The suggestion list SUGGESTS and never autofills. Typed text is only ever
//  replaced by an explicit tap on a suggestion; typing on, dismissing the
//  keyboard, or saving all keep exactly what the user wrote. Picking a
//  suggestion adopts the canonical string verbatim, which is what makes the
//  ingredient consolidate with built-in recipes in the grocery list.
//
//  The list expands INLINE beneath the field rather than floating over the
//  form. A floating overlay inside a ScrollView clips against neighbouring
//  cards and fights the keyboard; pushing the rows below it down always
//  renders correctly and keeps every suggestion tappable.
//

import SwiftUI

struct IngredientDraftRow: View {
    @Binding var draft: IngredientDraft
    let catalog: IngredientCatalog
    /// Row number shown in the leading pale circle (1-based).
    let index: Int
    let canRemove: Bool
    let onRemove: () -> Void

    @FocusState private var isNameFocused: Bool

    /// Live matches for what's typed. Empty while the field is unfocused, so
    /// the form collapses back to compact rows as soon as the user moves on.
    private var suggestions: [String] {
        guard isNameFocused else { return [] }
        let matches = catalog.suggestions(for: draft.name)
        // Nothing to offer when the text is already exactly the one match.
        if matches.count == 1, matches[0].caseInsensitiveCompare(draft.name) == .orderedSame {
            return []
        }
        return matches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameField
            if !suggestions.isEmpty {
                suggestionList
            }
            detailRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: suggestions)
    }

    // MARK: Name

    private var nameField: some View {
        HStack(spacing: 10) {
            Text(index.formatted())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.textOnPale)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.brandOrangePale))

            TextField("Ingredient", text: $draft.name)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isNameFocused)

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.textTertiary)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Remove ingredient")
            }
        }
    }

    // MARK: Suggestions

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    // The ONE place typed text is replaced, and only because
                    // the user tapped this exact row.
                    draft.name = suggestion
                    isNameFocused = false
                } label: {
                    HStack(spacing: 8) {
                        Text(suggestion)
                            .font(.system(size: 13))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if catalog.isUsedByBundledRecipes(suggestion) {
                            // Signals the grocery-list payoff: this exact
                            // string already appears in built-in recipes, so
                            // the two will merge onto one shopping row.
                            Image(systemName: "cart")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.textTertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))
        .padding(.leading, 32)
    }

    // MARK: Quantity, unit, preparation

    private var detailRow: some View {
        HStack(spacing: 8) {
            TextField("Qty", text: $draft.quantity)
                .font(.system(size: 13))
                .foregroundStyle(.textPrimary)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 56, height: 34)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))

            Menu {
                Picker("Unit", selection: $draft.unit) {
                    Text("No unit").tag(String?.none)
                    ForEach(IngredientCatalog.units, id: \.self) { unit in
                        Text(unit).tag(String?.some(unit))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(draft.unit ?? String(localized: "Unit"))
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(draft.unit == nil ? Color.chipTextUnselected : .textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))
            }

            TextField("Prep (optional)", text: $draft.preparation)
                .font(.system(size: 13))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))
        }
        .padding(.leading, 32)
    }
}
