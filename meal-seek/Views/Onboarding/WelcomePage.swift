//
//  WelcomePage.swift
//  Meal Seek
//
//  Onboarding screen 1: logo, app name, slogan.
//

import SwiftUI

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            RoundedRectangle(cornerRadius: 22)
                .fill(Color.brandOrange)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: SFSymbols.chefHat)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(verbatim: "Meal Seek")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.textPrimary)

            Text("Plan once. Eat all week.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}
