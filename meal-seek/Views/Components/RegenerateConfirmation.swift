//
//  RegenerateConfirmation.swift
//  Meal Seek
//
//  The single Regenerate confirmation shared by both entry points (Home's
//  refresh button and Account → Regenerate week) so the copy cannot drift.
//  A hand-edited week gets a destructive lose-your-swaps warning instead of
//  the plain replace prompt.
//

import SwiftUI

extension View {
    func regenerateConfirmation(
        isPresented: Binding<Bool>,
        hasManualEdits: Bool,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(
            hasManualEdits ? "Replace this week?" : "Regenerate this week?",
            isPresented: isPresented
        ) {
            Button(hasManualEdits ? "Keep my week" : "Cancel", role: .cancel) {}
            Button("Regenerate", role: hasManualEdits ? .destructive : nil, action: onConfirm)
        } message: {
            let message: LocalizedStringKey = hasManualEdits
                ? "You've swapped meals in this week. Regenerating deals a new plan and your changes will be lost."
                : "Your current plan will be replaced."
            Text(message)
        }
    }
}
