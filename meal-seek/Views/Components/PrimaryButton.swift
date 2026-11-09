//
//  PrimaryButton.swift
//  Meal Seek
//
//  Reusable full-width CTA button. Used by onboarding now; the Account screen
//  will reuse it later.
//

import SwiftUI

struct PrimaryButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    var style: Style = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    private var foreground: Color {
        style == .primary ? .white : .textOnPale
    }

    private var background: Color {
        style == .primary ? .brandOrange : .brandOrangePale
    }
}
