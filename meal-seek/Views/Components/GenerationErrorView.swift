//
//  GenerationErrorView.swift
//  Meal Seek
//
//  The designed, on-brand state shown when week generation fails outright. It
//  reads its copy from the `WeekGenerationError` so no raw Swift error text is
//  ever surfaced: a plain-language headline, one sentence on the likely cause,
//  a primary action appropriate to the case, and a lower-emphasis "Report this
//  problem" that hands a diagnostic to the existing share-sheet flow.
//
//  Reusable across surfaces: Home shows it inline in place of the meal list;
//  Account presents it in a sheet. The host decides what the primary action
//  does (switch to preferences vs. retry) by inspecting `error.primaryAction`.
//

import SwiftUI

struct GenerationErrorView: View {
    let error: WeekGenerationError
    /// Runs the primary action. The host branches on `error.primaryAction` to
    /// either send the user to their preferences or retry generation.
    let onPrimaryAction: () -> Void
    /// Assembles and shares the diagnostic via the share sheet.
    let onReport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.brandOrangePale)
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.brandOrange)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 8) {
                Text(error.userHeadline)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(error.userExplanation)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                PrimaryButton(title: error.primaryActionTitle, action: onPrimaryAction)
                PrimaryButton(title: String(localized: "Report this problem"), style: .secondary, action: onReport)
            }
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
