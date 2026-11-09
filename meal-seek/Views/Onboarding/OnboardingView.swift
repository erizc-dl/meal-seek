//
//  OnboardingView.swift
//  Meal Seek
//
//  4-page swipeable onboarding wizard. Pages edit the store's preferences in
//  place; "Build my week" marks onboarding complete and persists to disk.
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var store: PreferencesStore
    /// Source of the derived region → cuisine catalog for the cuisines page.
    let recipeStore: RecipeStore
    /// Runs after preferences are saved on the final page — the app uses this
    /// to generate the current week's plan before showing Home.
    var onComplete: () -> Void = {}

    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage()
                    .tag(0)
                RegionsPage(catalog: recipeStore.catalog, selected: $store.preferences.cuisines)
                    .tag(1)
                AllergiesPage(selected: $store.preferences.allergens)
                    .tag(2)
                ServingsPage(householdSize: $store.preferences.householdSize)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)

            footer
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

    private var footer: some View {
        VStack(spacing: 16) {
            pageDots
            PrimaryButton(title: buttonTitle, isEnabled: canAdvance, action: advance)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.brandOrange : .brandOrangePale)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var buttonTitle: String {
        switch page {
        case 0: return String(localized: "Get started")
        case pageCount - 1: return String(localized: "Build my week")
        default: return String(localized: "Continue")
        }
    }

    /// The cuisines page requires at least one cuisine; every other page is always valid.
    private var canAdvance: Bool {
        if page == 1 { return !store.preferences.cuisines.isEmpty }
        return true
    }

    private func advance() {
        if page < pageCount - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        store.preferences.hasCompletedOnboarding = true
        store.save()
        onComplete()
    }
}
