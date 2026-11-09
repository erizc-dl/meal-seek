//
//  ServingsStepper.swift
//  Meal Seek
//
//  Reusable [−] value [+] servings stepper card per the ui-design skill.
//  Used in onboarding now; the Account screen will reuse it later.
//

import SwiftUI

struct ServingsStepper: View {
    @Binding var value: Int
    /// Optional label shown above the row (e.g. "Cooking for" on Account).
    var label: LocalizedStringKey? = nil
    var minimum: Int = 1

    private var canDecrement: Bool { value > minimum }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label {
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.textTertiary)
            }
            HStack(spacing: 12) {
                minusButton
                valueField
                plusButton
            }
        }
        .padding(14)
        .background(.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var minusButton: some View {
        Button {
            if canDecrement { value -= 1 }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canDecrement ? Color.brandOrange : .textTertiary)
                .frame(width: 38, height: 38)
                .background(canDecrement ? Color.brandOrangePale : .backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!canDecrement)
    }

    private var plusButton: some View {
        Button {
            value += 1
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.brandOrange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var valueField: some View {
        HStack(spacing: 4) {
            Text(value.formatted())
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.textPrimary)
            Text("people")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
