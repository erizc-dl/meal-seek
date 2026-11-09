//
//  FilterChip.swift
//  Meal Seek
//
//  A dropdown filter chip: SelectableChip's exact anatomy plus a disclosure
//  chevron. "Active" (a non-default choice) renders as a selected chip.
//
//  Extracted from RecipeLibraryView, which grew it first, so the recipe library
//  and the dish picker cannot drift apart on chip geometry. Use it as a `Menu`
//  label; the menu itself stays with the caller, because only the caller knows
//  what it is choosing between.
//

import SwiftUI

struct FilterChip: View {
    let label: String
    /// True when the filter holds a non-default choice.
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isActive ? .white : Color.chipTextUnselected)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(isActive ? Color.brandOrange : .backgroundSecondary))
    }
}
