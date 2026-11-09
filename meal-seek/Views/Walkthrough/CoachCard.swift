//
//  CoachCard.swift
//  Meal Seek
//
//  The instruction card that rides alongside the spotlight.
//
//  No arrow, no tail, no pointer: the cutout is already pointing. An arrow would
//  be a second pointer aimed at the same thing.
//

import SwiftUI

struct CoachCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// Total steps and the current one, for the progress dots. Zero total hides
    /// the dots entirely (used while proving the engine).
    var stepIndex: Int = 0
    var stepCount: Int = 0
    /// Shown only on steps with nothing to DO -- an action step advances when
    /// the user performs the action, and a Next button there would let them
    /// skip past the thing they are meant to learn.
    var onNext: (() -> Void)?
    let onSkip: () -> Void

    /// Card width ceiling: the screen less the app's 20pt gutters.
    static let horizontalMargin: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            footer
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if stepCount > 0 {
                progressDots
            }

            Spacer(minLength: 8)

            if let onNext {
                // A compact text button, deliberately not a PrimaryButton: a
                // full-width orange bar would outweigh the control the user is
                // supposed to be looking at.
                Button(action: onNext) {
                    Text("Next")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.brandOrange)
                }
                .buttonStyle(PressableButtonStyle())
            }

            Button(action: onSkip) {
                Text("Skip")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textTertiary)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    /// The onboarding footer's dots, reused verbatim: 7pt, 8pt apart,
    /// `brandOrange` active on `brandOrangePale`.
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == stepIndex ? Color.brandOrange : .brandOrangePale)
                    .frame(width: 7, height: 7)
            }
        }
    }
}
