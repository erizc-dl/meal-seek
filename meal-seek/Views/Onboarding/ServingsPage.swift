//
//  ServingsPage.swift
//  Meal Seek
//
//  Onboarding screen 4: household size via the shared servings stepper.
//

import SwiftUI

struct ServingsPage: View {
    @Binding var householdSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How many are you cooking for?")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                Text("Sets your shopping amounts")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.textSecondary)
            }

            ServingsStepper(value: $householdSize)

            Text("You can change this anytime in Account.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
}
