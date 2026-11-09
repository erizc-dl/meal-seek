//
//  RecipeLibraryView.swift
//  Meal Seek
//
//  Account sub-screen: the full browsable recipe library. Search (name or
//  cuisine) combines with cuisine, meal-type, and rating filters; rows are
//  lazily rendered and push the recipe detail, where the user can rate.
//

import SwiftUI

struct RecipeLibraryView: View {
    let recipeStore: RecipeStore
    let ratingsStore: RatingsStore
    /// Forwarded to Add Recipe so a deletion can prune saved plans.
    let planStore: WeekPlanStore
    @Environment(\.walkthrough) private var walkthrough
    /// Display-layer localization of recipe names; also lets search match the
    /// translated name. Record identity (id, cuisine, ingredients) stays English.
    @Environment(\.recipeTranslations) private var translations

    @State private var searchText = ""
    /// nil = all cuisines / all meal types.
    @State private var cuisineFilter: String?
    @State private var mealTypeFilter: String?
    @State private var ratingFilter: RatingFilter = .all
    /// Narrows the list to the user's own recipes. Off by default — user
    /// recipes are peers of the built-ins, not a separate section.
    @State private var showsOnlyUserRecipes = false

    enum RatingFilter: String, CaseIterable {
        case all = "All"
        case liked = "Liked"
        case disliked = "Disliked"

        /// Localized display label (the rawValue stays an English key).
        var localizedName: String {
            switch self {
            case .all: return String(localized: "All")
            case .liked: return String(localized: "Liked")
            case .disliked: return String(localized: "Disliked")
            }
        }
    }

    private var cuisines: [String] {
        Set(recipeStore.recipes.map(\.cuisine)).sorted()
    }

    /// The one pure filter: search and every dropdown are ANDed together.
    private var results: [Recipe] {
        var pool = recipeStore.recipes
        if showsOnlyUserRecipes {
            pool = pool.filter { UserRecipeStore.isUserRecipe(id: $0.id) }
        }
        if let cuisineFilter {
            pool = pool.filter { $0.cuisine == cuisineFilter }
        }
        if let mealTypeFilter {
            pool = pool.filter { $0.mealTypes.contains(mealTypeFilter) }
        }
        switch ratingFilter {
        case .all:
            break
        case .liked:
            pool = pool.filter { ratingsStore.rating(for: $0.id) == .liked }
        case .disliked:
            pool = pool.filter { ratingsStore.rating(for: $0.id) == .disliked }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            pool = pool.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.cuisine.localizedCaseInsensitiveContains(query)
                    || translations.name(for: $0).localizedCaseInsensitiveContains(query)
            }
        }
        // Order by the name the user is reading (the active-language display
        // name), not the canonical English name — so the list is alphabetical to
        // them. Record identity and eligibility filtering stay canonical English;
        // search also matches the translated display name.
        return translations.sortedByDisplayName(pool)
    }

    var body: some View {
        let results = self.results

        VStack(alignment: .leading, spacing: 14) {
            searchField
            filterRow
            countLine(results.count)

            if results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, recipe in
                                row(recipe)
                                    // Only the first row claims the step, so
                                    // exactly one view registers it however
                                    // long the list is.
                                    .spotlightTarget(index == 0 ? .openRecipe : nil, cornerRadius: 12)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .animation(.easeInOut(duration: 0.25), value: results.map(\.id))
                    // Bring the target into view BEFORE its cutout is drawn.
                    // Scrolling to the top is enough here because the target is
                    // the first row -- and it avoids putting an .id() on a row
                    // inside a ForEach, which would fight the list's own
                    // identity and its filter animation.
                    .onChange(of: walkthrough.isPreparing) { _, preparing in
                        guard preparing, walkthrough.step == .openRecipe,
                              let first = results.first?.id else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scrollProxy.scrollTo(first, anchor: .top)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .spotlightScreen()
        // "The library appeared", not "the link was tapped": a tap that does
        // not result in a push must not advance step 7.
        .onAppear { walkthrough.report(.openedRecipeLibrary) }
        .navigationTitle("Recipe library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddRecipeView(recipeStore: recipeStore, planStore: planStore)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandOrange)
                }
                .accessibilityLabel("Add recipe")
            }
        }
    }

    // MARK: Search (same visual spec as the Grocery search field)

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.textTertiary)
            TextField("Search recipes", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundCard))
    }

    // MARK: Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Picker("Cuisine", selection: $cuisineFilter) {
                        Text("All cuisines").tag(String?.none)
                        ForEach(cuisines, id: \.self) { cuisine in
                            Text(LocalizedNames.cuisine(cuisine)).tag(String?.some(cuisine))
                        }
                    }
                } label: {
                    filterChip(cuisineFilter.map(LocalizedNames.cuisine) ?? String(localized: "Cuisine"), isActive: cuisineFilter != nil)
                }

                Menu {
                    Picker("Meal", selection: $mealTypeFilter) {
                        Text("All meals").tag(String?.none)
                        ForEach(PlanGenerator.mealTypes, id: \.self) { mealType in
                            Text(LocalizedNames.mealType(mealType)).tag(String?.some(mealType))
                        }
                    }
                } label: {
                    filterChip(mealTypeFilter.map(LocalizedNames.mealType) ?? String(localized: "Meal"), isActive: mealTypeFilter != nil)
                }

                Menu {
                    Picker("Rating", selection: $ratingFilter) {
                        ForEach(RatingFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedName).tag(filter)
                        }
                    }
                } label: {
                    filterChip(ratingFilter == .all ? String(localized: "Rating") : ratingFilter.localizedName, isActive: ratingFilter != .all)
                }

                // Only worth offering once the user has recipes of their own.
                if !recipeStore.userRecipes.recipes.isEmpty {
                    SelectableChip(
                        label: String(localized: "Mine"),
                        isSelected: showsOnlyUserRecipes,
                        action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showsOnlyUserRecipes.toggle()
                            }
                        }
                    )
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Now `Views/Components/FilterChip.swift`, shared with the dish picker.
    /// Kept as a thin forwarder so this screen's three call sites read the same
    /// as they always did.
    private func filterChip(_ label: String, isActive: Bool) -> some View {
        FilterChip(label: label, isActive: isActive)
    }

    // MARK: Count & empty state

    private func countLine(_ count: Int) -> some View {
        // Lowercase key + .textCase(.uppercase), NOT an uppercase literal.
        // "%lld RECIPES" and "%lld recipes" generate the same String Catalog
        // symbol — .recipes(_ arg1: Int) — because symbol generation is
        // case-insensitive, and two keys differing only in case fail the build.
        // They rendered the same words in all three languages anyway (identical
        // in zh-Hans, which has no case), so the casing was presentation baked
        // into the data.
        //
        // This is the only .textCase in the app: every other uppercase header
        // is a static literal with no plural and no count, so none of them has
        // a lowercase twin to collide with. Only a COUNTED string needs the
        // same key in both cases, which is what made this one collide.
        Text("\(count) recipes")
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.textTertiary)
            .padding(.leading, 2)
    }

    private var emptyState: some View {
        Text(showsOnlyUserRecipes && recipeStore.userRecipes.recipes.isEmpty
             ? "You haven't added a recipe yet"
             : "No recipes match")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    // MARK: Row

    private func row(_ recipe: Recipe) -> some View {
        NavigationLink {
            RecipeDetailView(recipe: recipe, ratingsStore: ratingsStore,
                             recipeStore: recipeStore, planStore: planStore)
        } label: {
            HStack(spacing: 12) {
                RecipeSymbol(recipe: recipe, size: 46)
                    .userRecipeBadge(UserRecipeStore.isUserRecipe(id: recipe.id))

                Text(translations.name(for: recipe))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(LocalizedNames.cuisine(recipe.cuisine)) · \(recipe.prepTimeMinutes + recipe.cookTimeMinutes)m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.textOnPale)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.brandOrangePale))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundCard)
                    .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
