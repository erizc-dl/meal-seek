//
//  AddRecipeView.swift
//  Meal Seek
//
//  Structured entry for a user's own recipe, and the edit screen for one
//  already saved. Everything is typed into fields — there is no free-text
//  paste-and-parse — so what comes out is a real `Recipe` the planner, the
//  grocery list, and the allergen filter can all consume unchanged.
//
//  Two things carry the safety weight:
//
//  - Ingredient names get canonical SUGGESTIONS (never autofill) so a user's
//    "tomato" is the same string as a built-in recipe's and merges into one
//    grocery row. Unmatched names save exactly as typed.
//  - Allergens are DERIVED from those names and then CONFIRMED by the user,
//    with the deriving ingredient shown next to each chip. The saved recipe's
//    `allergens` is what feeds `RecipeFilter.allergenSafe`, identical to a
//    built-in recipe — a user recipe is filtered by exactly the same path.
//

import SwiftUI

struct AddRecipeView: View {
    let recipeStore: RecipeStore
    /// Required so deleting a recipe can strip it from saved plans in the same
    /// step — see RecipeStore.deleteUserRecipe(id:planStore:).
    let planStore: WeekPlanStore
    /// nil when creating. Non-nil edits that existing user recipe in place,
    /// keeping its id so ratings and planned meals still point at it.
    var editing: Recipe?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeDraft
    @State private var showDeleteConfirmation = false

    init(recipeStore: RecipeStore, planStore: WeekPlanStore, editing: Recipe? = nil) {
        self.recipeStore = recipeStore
        self.planStore = planStore
        self.editing = editing
        _draft = State(initialValue: editing.map(RecipeDraft.init(editing:)) ?? RecipeDraft())
    }

    private var isEditing: Bool { editing != nil }

    /// Planned dishes that would go with this recipe, for the delete
    /// confirmation. Read-only; computed when the dialog is built.
    private var plannedDishCount: Int {
        planStore.plannedDishCount(forRecipe: draft.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                basicsCard
                timingCard

                sectionHeader("INGREDIENTS")
                ingredientRows
                addRowButton("Add ingredient") {
                    draft.ingredients.append(IngredientDraft())
                }

                sectionHeader("STEPS")
                instructionRows
                addRowButton("Add step") {
                    draft.instructions.append(InstructionDraft())
                }

                sectionHeader("ALLERGENS")
                allergenCard

                saveSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isEditing ? "Edit recipe" : "New recipe")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: draft.ingredients.count)
        .animation(.easeInOut(duration: 0.25), value: draft.instructions.count)
        // Pre-select the proposed dish type as the ingredients change, but
        // NEVER over a value the user chose — the same discipline the allergen
        // chips use with userAdded/userRemoved. Adding a tenth ingredient can't
        // silently re-classify a dish the user already classified.
        //
        // Keyed on the ingredient NAMES rather than the count, because editing
        // a name in place is exactly the edit that changes the proposal, and
        // the count does not move when it happens.
        .onChange(of: draft.ingredients.map(\.name)) {
            guard draft.role == nil, let proposed = draft.proposedRole else { return }
            withAnimation(.easeInOut(duration: 0.25)) { draft.role = proposed }
        }
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                recipeStore.deleteUserRecipe(id: draft.id, planStore: planStore)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Counted, not promised. The old copy said "Planned meals using it
            // will be dropped" while nothing pruned anything — so it was both a
            // false statement and, once true, still vaguer than it needed to be.
            // Saying the number BEFORE the user commits beats a toast afterwards:
            // a deletion is not undoable, and this is the moment the information
            // is worth anything.
            Text(plannedDishCount > 0
                 ? String(localized: "This removes it from your library and drops it from \(plannedDishCount) planned meals.")
                 : String(localized: "This removes it from your library. No planned meals use it."))
        }
    }

    // MARK: Basics

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Name")
            TextField("e.g. Sunday lentil soup", text: $draft.name)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))

            fieldLabel("Cuisine")
            Menu {
                Picker("Cuisine", selection: $draft.cuisine) {
                    ForEach(cuisineNames, id: \.self) { cuisine in
                        Text(LocalizedNames.cuisine(cuisine)).tag(cuisine)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(draft.cuisine.isEmpty
                         ? String(localized: "Choose a cuisine")
                         : LocalizedNames.cuisine(draft.cuisine))
                        .font(.system(size: 14, weight: .medium))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(draft.cuisine.isEmpty ? Color.chipTextUnselected : .textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))
            }

            fieldLabel("Meals")
            FlowLayout(spacing: 10) {
                ForEach(PlanGenerator.mealTypes, id: \.self) { mealType in
                    SelectableChip(
                        label: LocalizedNames.mealType(mealType),
                        isSelected: draft.mealTypes.contains(mealType),
                        action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if draft.mealTypes.contains(mealType) {
                                    draft.mealTypes.remove(mealType)
                                } else {
                                    draft.mealTypes.insert(mealType)
                                }
                            }
                        }
                    )
                }
            }

            dishTypeField
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        )
    }

    // MARK: Dish type

    /// Four chips, single-select, sitting directly under Meals because a dish's
    /// role is a basics-level fact of the same kind — and rendered with the same
    /// `SelectableChip` in the same `FlowLayout` so it reads as the same kind of
    /// question. Chips rather than the cuisine field's `Menu` because there are
    /// four fixed options, and because the user has to SEE that All-in-one
    /// exists in order to read what it means.
    ///
    /// Called "Dish type", not "Role": `role` is the data layer's word for it,
    /// and the user has no reason to learn it.
    private var dishTypeField: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Dish type")

            FlowLayout(spacing: 10) {
                ForEach(DishRole.userSelectable, id: \.self) { role in
                    SelectableChip(
                        label: LocalizedNames.role(role.rawValue),
                        isSelected: draft.role == role,
                        action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                // Single-select: tapping the chosen one again
                                // does NOT clear it. Role is required, so an
                                // empty state is not somewhere a tap should be
                                // able to strand the user.
                                draft.role = role
                            }
                        }
                    )
                }
            }

            // Soup is a property of a side dish and of nothing else, so the
            // control does not exist for the other three. A SelectableChip
            // rather than a Toggle: it sits among chips, and the app's single
            // Toggle lives in a settings list, which is a different anatomy.
            if draft.showsSoupToggle {
                SelectableChip(
                    label: String(localized: "Soup"),
                    isSelected: draft.isSoup,
                    action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            draft.isSoup.toggle()
                        }
                    }
                )
                .transition(.opacity)
            }

            // Same "proposed, visible, overridable" note the allergen card
            // carries, in the same 12 regular textSecondary.
            if draft.proposedRole != nil {
                Text("Proposed from your ingredients. Change it if it's wrong.")
                    .font(.system(size: 12))
                    .foregroundStyle(.textSecondary)
            }

            // Without this people pick All-in-one for everything, because every
            // recipe feels complete to the person who wrote it.
            Text("All-in-one is a complete meal on its own, like a pasta dish or a sandwich. The others are served together.")
                .font(.system(size: 11))
                .foregroundStyle(.textTertiary)
        }
    }

    /// Cuisines the bundled database already has. Deliberately not free text:
    /// a user recipe reuses an existing cuisine so it stays inside the
    /// region/cuisine catalog every filter and preference screen is built on.
    private var cuisineNames: [String] {
        recipeStore.catalog.allCuisineNames.sorted()
    }

    // MARK: Timing

    /// Servings reuses `ServingsStepper` as its own card rather than being
    /// re-laid-out inside another one — it already is a radius-16 card (with
    /// the missing shadow catalogued as Open Inconsistency #4).
    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ServingsStepper(value: $draft.baseServings, label: "Serves")

            HStack(spacing: 12) {
                minutesField("Prep (min)", value: $draft.prepTimeMinutes)
                minutesField("Cook (min)", value: $draft.cookTimeMinutes)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.backgroundCard)
                    .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
            )
        }
    }

    private func minutesField(_ label: LocalizedStringKey, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField("0", value: value, format: .number)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary))
        }
    }

    // MARK: Ingredients & steps

    // Rows are addressed by the draft's stable UUID, never by index: index
    // identity would let a removal mid-animation bind a row to the wrong
    // element (and its text field to the wrong text).
    private var ingredientRows: some View {
        VStack(spacing: 8) {
            ForEach(draft.ingredients) { ingredient in
                if let index = draft.ingredients.firstIndex(where: { $0.id == ingredient.id }) {
                    IngredientDraftRow(
                        draft: $draft.ingredients[index],
                        catalog: recipeStore.ingredientCatalog,
                        index: index + 1,
                        canRemove: draft.ingredients.count > 1,
                        onRemove: { draft.ingredients.removeAll { $0.id == ingredient.id } }
                    )
                }
            }
        }
    }

    private var instructionRows: some View {
        VStack(spacing: 8) {
            ForEach(draft.instructions) { instruction in
                if let index = draft.instructions.firstIndex(where: { $0.id == instruction.id }) {
                    HStack(alignment: .top, spacing: 10) {
                        Text((index + 1).formatted())
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.textOnPale)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.brandOrangePale))

                        TextField("What happens in this step?", text: $draft.instructions[index].text, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1...6)

                        if draft.instructions.count > 1 {
                            Button {
                                draft.instructions.removeAll { $0.id == instruction.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.textTertiary)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("Remove step")
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.backgroundCard)
                            .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
                    )
                }
            }
        }
    }

    private func addRowButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.textOnPale)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.brandOrangePale))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: Allergens

    private var allergenCard: some View {
        let sources = draft.sourcesByAllergen()
        let selected = draft.effectiveAllergens

        return VStack(alignment: .leading, spacing: 12) {
            Text("Ticked from your ingredients. Check them before saving — these are what keep this recipe out of meals you can't eat.")
                .font(.system(size: 12))
                .foregroundStyle(.textSecondary)

            FlowLayout(spacing: 10) {
                ForEach(AllergenTable.allTracked, id: \.self) { allergen in
                    SelectableChip(
                        label: LocalizedNames.allergen(allergen),
                        isSelected: selected.contains(allergen),
                        action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                draft.toggleAllergen(allergen)
                            }
                        }
                    )
                }
            }

            // Why each chip is ticked. Without this the user is asked to
            // trust a pre-ticked safety control they can't see the basis for.
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sources.keys.sorted(), id: \.self) { allergen in
                        Text("\(LocalizedNames.allergen(allergen)) — from \(sources[allergen, default: []].joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundStyle(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Text("Best-effort matching on ingredient names, not a medical guarantee. Always check labels.")
                .font(.system(size: 11))
                .foregroundStyle(.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        )
    }

    // MARK: Save

    private var saveSection: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: isEditing ? String(localized: "Save changes") : String(localized: "Save recipe"),
                isEnabled: draft.isSaveable,
                action: save
            )

            // The reason the button is disabled has to carry as much weight as
            // the disabled button itself. As 11pt textTertiary — the faintest
            // style in the system — it read as a footnote, and a user who had
            // filled name, meals, ingredients and steps could not tell that
            // the untouched cuisine picker was what was holding save back.
            // Pale capsule + textOnPale is the app's existing emphasis
            // pattern; no new hue, and none is available (Section 10).
            if let message = draft.validationMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textOnPale)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.brandOrangePale))
                    .transition(.opacity)
            }

            if isEditing {
                Button("Delete recipe") { showDeleteConfirmation = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 6)
    }

    private func save() {
        recipeStore.saveUserRecipe(draft.makeRecipe(catalog: recipeStore.catalog))
        dismiss()
    }

    // MARK: Small shared pieces

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.textTertiary)
            .padding(.leading, 2)
            .padding(.top, 6)
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.textTertiary)
    }
}
