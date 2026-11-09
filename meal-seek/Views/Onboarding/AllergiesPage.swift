//
//  AllergiesPage.swift
//  Meal Seek
//
//  Onboarding screen 3: multi-select allergens as wrapping capsule chips.
//

import SwiftUI

struct AllergiesPage: View {
    @Binding var selected: Set<String>

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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anything to avoid?")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                Text("We'll leave these out")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.textSecondary)
            }

            FlowLayout(spacing: 10) {
                ForEach(allergens, id: \.value) { allergen in
                    SelectableChip(
                        label: LocalizedNames.allergen(allergen.value),
                        isSelected: selected.contains(allergen.value),
                        action: { toggle(allergen.value) }
                    )
                }
            }

            Text("Best-effort filtering, not a medical guarantee. Always check labels.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private func toggle(_ value: String) {
        if selected.contains(value) {
            selected.remove(value)
        } else {
            selected.insert(value)
        }
    }
}
