//
//  GeneratorLabView.swift
//  Meal Seek
//
//  DEBUG-ONLY test screen for the Task 3 generator, so the owner can try the
//  three paths, the allergy/diet filter, servings and the grocery list before
//  the real screens exist. Opened from the 🧪 button (see MealSeekApp). Not
//  compiled into release builds, and it saves nothing.
//

#if DEBUG
import SwiftUI

struct GeneratorLabView: View {
    let recipeStore: RecipeStore
    @Environment(\.dismiss) private var dismiss

    enum Path: String, CaseIterable, Identifiable {
        case fridge = "1 · Fridge"
        case plan = "2 · Plan"
        case pick = "3 · Pick"
        var id: String { rawValue }
    }

    @State private var allergens: Set<String> = []
    @State private var diets: Set<String> = []
    @State private var units = MeasurementSystem.metric
    @State private var path = Path.fridge

    @State private var ingredientText = ""
    @State private var fridge: [String] = []
    @State private var fridgeCuisines: Set<String> = []
    @State private var planCuisines: Set<String> = []
    @State private var preferences: Set<String> = []
    @State private var search = ""
    @State private var scope = Recommender.LibraryScope.all

    @State private var selected: [String] = []
    @State private var servings = 2
    @State private var safetyReport: String?

    private var profile: SafetyProfile { SafetyProfile(allergens: allergens, diets: diets) }
    private var recipes: [Recipe] { recipeStore.recipes }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                Section {
                    Picker("Path", selection: $path) {
                        ForEach(Path.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch path {
                case .fridge: fridgeSections
                case .plan: planSections
                case .pick: pickSections
                }
                selectionSection
                safetySection
            }
            .navigationTitle("Generator test lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        Section("Who's cooking (applies to every path)") {
            DisclosureGroup("Allergies (\(allergens.count))") {
                ForEach(SafetyProfile.allAllergens, id: \.self) { key in
                    Toggle(key.replacingOccurrences(of: "_", with: " ").capitalized, isOn: binding(key, in: $allergens))
                }
            }
            DisclosureGroup("Diets (\(diets.count))") {
                ForEach(SafetyProfile.allDiets, id: \.self) { key in
                    Toggle(key.capitalized, isOn: binding(key, in: $diets))
                }
            }
            Picker("Units", selection: $units) {
                Text("Metric").tag(MeasurementSystem.metric)
                Text("Imperial").tag(MeasurementSystem.imperial)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Path 1

    @ViewBuilder private var fridgeSections: some View {
        Section("My ingredients (required)") {
            HStack {
                TextField("Add an ingredient", text: $ingredientText)
                    .textInputAutocapitalization(.never)
                    .onSubmit { addIngredient(ingredientText) }
                Button("Add") { addIngredient(ingredientText) }
                    .disabled(ingredientText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            let suggestions = recipeStore.ingredientCatalog.suggestions(for: ingredientText, limit: 6)
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) { addIngredient(name) }.buttonStyle(.bordered).font(.caption)
                    }
                }
            }
            if !fridge.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(fridge, id: \.self) { name in
                        Button { fridge.removeAll { $0 == name } } label: {
                            Label(name, systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent).tint(.brandOrange).font(.caption)
                    }
                }
            }
        }
        Section("Cuisine preferences (optional)") {
            cuisineGrid($fridgeCuisines)
        }
        let result = Recommender.fridge(ingredients: fridge, cuisines: fridgeCuisines, recipes: recipes, profile: profile)
        Section {
            filterBanner(hidden: result.hiddenCount)
            if fridge.isEmpty { Text("Add at least one ingredient.").foregroundStyle(.secondary) }
            ForEach(result.matches) { match in
                recipeRow(match.recipe) {
                    Text("Uses \(match.matchCount) of yours · \(match.percent)% match\(match.isPreferredCuisine ? " · picked cuisine" : "")")
                        .font(.caption).bold()
                    if !match.have.isEmpty {
                        Text("✓ " + match.have.joined(separator: ", ")).font(.caption).foregroundStyle(.green)
                    }
                    if !match.missing.isEmpty {
                        Text("✗ " + match.missing.joined(separator: ", ")).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("Recipes for you (top \(Recommender.fridgeLimit))")
        }
    }

    // MARK: Path 2

    @ViewBuilder private var planSections: some View {
        Section("Cuisines (pick at least one)") {
            cuisineGrid($planCuisines)
        }
        Section("Meal preferences (optional)") {
            ForEach(Recommender.mealPreferences, id: \.self) { key in
                Toggle(preferenceLabel(key), isOn: binding(key, in: $preferences))
            }
        }
        let result = Recommender.plan(cuisines: planCuisines, preferences: preferences, recipes: recipes, profile: profile)
        Section("Recipes for you (\(result.matches.count))") {
            filterBanner(hidden: result.hiddenCount)
            if planCuisines.isEmpty { Text("Pick a cuisine first.").foregroundStyle(.secondary) }
            ForEach(result.matches) { match in
                recipeRow(match.recipe) {
                    if !match.metPreferences.isEmpty {
                        Text("Meets: " + match.metPreferences.map(preferenceLabel).joined(separator: ", "))
                            .font(.caption).bold()
                    }
                }
            }
        }
    }

    // MARK: Path 3

    @ViewBuilder private var pickSections: some View {
        Section("Choose your meal") {
            Picker("Show", selection: $scope) {
                Text("All").tag(Recommender.LibraryScope.all)
                ForEach(Recommender.cuisines, id: \.self) { Text($0).tag(Recommender.LibraryScope.cuisine($0)) }
                ForEach(SafetyProfile.allDiets, id: \.self) { Text($0.capitalized).tag(Recommender.LibraryScope.diet($0)) }
            }
            TextField("Search recipes", text: $search)
        }
        let result = Recommender.library(recipes: recipes, profile: profile, scope: scope, search: search)
        Section("\(result.recipes.count) recipes") {
            filterBanner(hidden: result.hiddenCount)
            ForEach(result.recipes) { recipe in
                recipeRow(recipe) { EmptyView() }
            }
        }
    }

    // MARK: Selection → servings → grocery

    private var selectionSection: some View {
        Section("Your picks (\(selected.count))") {
            ForEach(selected, id: \.self) { id in
                Text(recipes.first { $0.id == id }?.name ?? id)
            }
            Stepper("Cooking for \(servings) \(servings == 1 ? "person" : "people")", value: $servings, in: 1...20)
            NavigationLink("🛒 Make grocery list") {
                LabGroceryView(recipes: recipes, recipeIDs: selected, servings: servings, units: units)
            }
            .disabled(selected.isEmpty)
            if !selected.isEmpty {
                Button("Clear picks", role: .destructive) { selected.removeAll() }
            }
        }
    }

    // MARK: Safety check

    private var safetySection: some View {
        Section {
            Button("Run safety check") { safetyReport = runSafetyCheck() }
            if let safetyReport { Text(safetyReport).font(.callout) }
        } header: {
            Text("Safety check")
        } footer: {
            Text("Tries all 8,192 allergy + diet combinations on every recipe and compares the app's filter with a separate check. The full tests (tests/run-generator-tests.sh) run on the Mac.")
        }
    }

    /// Every allergy/diet combination against a rule written out here again,
    /// separately from RecipeFilter.
    private func runSafetyCheck() -> String {
        var problems = 0
        var combos = 0
        for a in 0..<(1 << SafetyProfile.allAllergens.count) {
            for d in 0..<(1 << SafetyProfile.allDiets.count) {
                combos += 1
                let allergens = Set(SafetyProfile.allAllergens.indices.filter { a & (1 << $0) != 0 }.map { SafetyProfile.allAllergens[$0] })
                let diets = Set(SafetyProfile.allDiets.indices.filter { d & (1 << $0) != 0 }.map { SafetyProfile.allDiets[$0] })
                let shown = Set(RecipeFilter.safe(recipes, for: SafetyProfile(allergens: allergens, diets: diets)).recipes.map(\.id))
                for recipe in recipes {
                    let fits = Set(recipe.dietRestrictions)
                    let ok = Set(recipe.allergens).isDisjoint(with: allergens)
                        && diets.allSatisfy { fits.contains($0) || ($0 == "vegetarian" && fits.contains("vegan")) }
                    if ok != shown.contains(recipe.id) { problems += 1 }
                }
            }
        }
        return problems == 0
            ? "✅ Passed: \(combos) combinations × \(recipes.count) recipes, no mistakes."
            : "❌ \(problems) mistakes found. Please tell Claude."
    }

    // MARK: Pieces

    private func filterBanner(hidden: Int) -> some View {
        let parts = allergens.sorted().map { "no " + $0.replacingOccurrences(of: "_", with: " ") } + diets.sorted()
        return Text(parts.isEmpty
                    ? "No allergies or diets set · nothing hidden"
                    : "🛡 Filtered for you: \(parts.joined(separator: " · ")) · \(hidden) hidden")
            .font(.caption)
            .foregroundStyle(Color(hex: "#1E7B4D"))
    }

    private func recipeRow<Extra: View>(_ recipe: Recipe, @ViewBuilder extra: () -> Extra) -> some View {
        Button { toggle(recipe.id) } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.name).font(.subheadline).bold().foregroundStyle(Color.textPrimary)
                    Text("\(recipe.cuisine) · \(recipe.prepTimeMinutes + recipe.cookTimeMinutes) min"
                         + (recipe.cuisineType.isEmpty ? "" : " · " + recipe.cuisineType.map(preferenceLabel).joined(separator: ", ")))
                        .font(.caption).foregroundStyle(.secondary)
                    if !recipe.dietRestrictions.isEmpty {
                        Text("🌿 " + recipe.dietRestrictions.map(\.capitalized).joined(separator: ", "))
                            .font(.caption).foregroundStyle(Color(hex: "#1E7B4D"))
                    }
                    if !recipe.allergens.isEmpty {
                        Text("ⓘ " + recipe.allergens.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    extra()
                }
                Spacer()
                Image(systemName: selected.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.brandOrange)
            }
        }
    }

    private func cuisineGrid(_ picked: Binding<Set<String>>) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Recommender.cuisines, id: \.self) { cuisine in
                let on = picked.wrappedValue.contains(cuisine)
                Button(cuisine) {
                    if on { picked.wrappedValue.remove(cuisine) } else { picked.wrappedValue.insert(cuisine) }
                }
                .buttonStyle(.bordered)
                .tint(on ? .brandOrange : .gray)
                .font(.caption)
            }
        }
    }

    private func preferenceLabel(_ key: String) -> String {
        switch key {
        case "low_budget": return "Low budget"
        case "under_30_min": return "Under 30 min"
        case "low_calorie": return "Low calorie"
        default: return key
        }
    }

    private func addIngredient(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !fridge.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            fridge.append(trimmed)
        }
        ingredientText = ""
    }

    private func toggle(_ id: String) {
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) } else { selected.append(id) }
    }

    private func binding(_ key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(key) },
            set: { on in if on { set.wrappedValue.insert(key) } else { set.wrappedValue.remove(key) } }
        )
    }
}

/// The grocery list and scaled ingredients for the lab's picks.
private struct LabGroceryView: View {
    let recipes: [Recipe]
    let recipeIDs: [String]
    let servings: Int
    let units: MeasurementSystem
    @State private var tab = "all"

    var body: some View {
        let plan = GroceryPlanner.build(recipeIDs: recipeIDs, recipes: recipes, servings: servings, units: units)
        let items = tab == "all" ? plan.all : plan.byRecipe.first { $0.recipeID == tab }?.items ?? []
        List {
            Section {
                Text("\(recipeIDs.count) recipes · amounts for \(servings) people")
                if recipeIDs.count > 1 {
                    Picker("Show", selection: $tab) {
                        Text("All").tag("all")
                        ForEach(plan.byRecipe, id: \.recipeID) { entry in
                            Text(name(entry.recipeID)).tag(entry.recipeID)
                        }
                    }
                }
            }
            Section("To buy") {
                ForEach(items.filter { !$0.isPantryStaple }) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.displayQuantity.map { $0 + "  " } ?? "")\(item.name)")
                        let notes = [item.neededAmount.map { "uses \($0)" }, item.recipeCount > 1 ? "\(item.recipeCount) recipes" : nil]
                            .compactMap { $0 }
                        if !notes.isEmpty {
                            Text(notes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Check your pantry (no amount)") {
                ForEach(items.filter(\.isPantryStaple)) { Text($0.name) }
            }
            ForEach(recipeIDs.filter { tab == "all" || tab == $0 }, id: \.self) { id in
                if let recipe = recipes.first(where: { $0.id == id }) {
                    Section("\(recipe.name): ingredients for \(servings)") {
                        ForEach(Array(RecipeScaling.ingredients(of: recipe, forServings: servings).enumerated()), id: \.offset) {
                            Text($0.element.displayText).font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle("Grocery list")
    }

    private func name(_ id: String) -> String {
        recipes.first { $0.id == id }?.name ?? id
    }
}
#endif
