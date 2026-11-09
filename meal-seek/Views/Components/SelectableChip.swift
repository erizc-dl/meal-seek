//
//  SelectableChip.swift
//  Meal Seek
//
//  Reusable capsule chip with a selected/unselected state. Used for allergen
//  selection now; reusable by the Account screen later.
//

import SwiftUI

struct SelectableChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : .chipTextUnselected)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.brandOrange : .backgroundSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
