//
//  RegionsPage.swift
//  Meal Seek
//
//  Onboarding screen 2: pick cuisines, grouped under expandable region cards
//  derived from the recipe database.
//

import SwiftUI

struct RegionsPage: View {
    let catalog: CuisineCatalog
    /// Selected cuisine names, bound to preferences.
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What do you like to cook?")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                Text("Pick one or more")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.textSecondary)
            }

            ScrollView {
                RegionCuisinePicker(catalog: catalog, selection: $selected)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
}
