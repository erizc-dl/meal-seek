//
//  RecipeDraft.swift
//  Meal Seek
//
//  The editable working copy behind AddRecipeView. Keeps every field as the
//  loose, partially-filled text a form actually holds, and converts to a real
//  `Recipe` only once on save — so a half-typed quantity is never a malformed
//  recipe, and the same screen edits an existing user recipe by loading one
//  back into a draft.
//
//  Allergens are the one field with memory. They are derived from the
//  ingredient names on every edit (see AllergenTable), but a derived value
//  must never overwrite a decision the user made: `userAdded` and
//  `userRemoved` record explicit taps, and the effective selection is always
//  (derived − userRemoved) ∪ userAdded. Adding a tenth ingredient therefore
//  can't silently re-tick an allergen the user deliberately cleared.
//

import Foundation

struct RecipeDraft {
    var id: String
    var name: String = ""
    var cuisine: String = ""
    var mealTypes: Set<String> = []
    var baseServings: Int = 2
    var prepTimeMinutes: Int = 10
    var cookTimeMinutes: Int = 20
    var ingredients: [IngredientDraft] = [IngredientDraft()]
    var instructions: [InstructionDraft] = [InstructionDraft()]

    /// Allergens the user ticked that the table did not derive.
    var userAdded: Set<String> = []
    /// Allergens the table derived that the user explicitly unticked.
    var userRemoved: Set<String> = []

    /// What part of a meal this dish plays. Optional because it is REQUIRED
    /// and must therefore be representable as unset — `.unassigned` is what an
    /// older file decodes to, never a choice, so it is not usable as "not
    /// picked yet". Nil blocks save.
    ///
    /// The form pre-selects `proposedRole` into this whenever it is nil, which
    /// is the "proposed, visible, overridable" shape the allergen chips already
    /// use. It is never written over a value the user chose.
    var role: DishRole?

    /// Whether this dish is a soup. Only meaningful when `role == .side`, and
    /// `makeRecipe` enforces that on the way out, so flipping the toggle and
    /// then changing the role away from Side cannot save a stray flag.
    var isSoup: Bool = false

    /// A blank draft for a brand-new recipe.
    init() {
        id = UserRecipeStore.makeID()
    }

    /// Loads an existing user recipe back into an editable draft. The stored
    /// allergens are treated as user-confirmed: whatever the table would
    /// derive now, the saved set is what the user last agreed to, so any
    /// difference is recorded as an explicit add or removal.
    init(editing recipe: Recipe) {
        id = recipe.id
        name = recipe.name
        cuisine = recipe.cuisine
        mealTypes = Set(recipe.mealTypes)
        baseServings = recipe.baseServings
        prepTimeMinutes = recipe.prepTimeMinutes
        cookTimeMinutes = recipe.cookTimeMinutes
        ingredients = recipe.ingredients.map(IngredientDraft.init(_:))
        instructions = recipe.instructions.map(InstructionDraft.init(text:))
        if ingredients.isEmpty { ingredients = [IngredientDraft()] }
        if instructions.isEmpty { instructions = [InstructionDraft()] }

        // `.unassigned` loads as nil, not as a role. Every user recipe saved
        // before the role field existed decodes that way, and re-opening one
        // should put the user in front of a proposal to confirm — the same
        // place a new draft starts — rather than silently keeping the value
        // that makes it invisible to slot-based generation.
        role = recipe.role == .unassigned ? nil : recipe.role
        isSoup = recipe.isSoup

        let saved = Set(recipe.allergens)
        let derived = AllergenTable.allergens(for: recipe.ingredients)
        userAdded = saved.subtracting(derived)
        userRemoved = derived.subtracting(saved)
    }

    // MARK: Role

    /// What the ingredients imply on their own, or nil when there is nothing
    /// to go on yet. Only ever `.main` or `.allInOne` — see
    /// `DishRoleDerivation` for why `side` and `staple` are out of reach.
    var proposedRole: DishRole? {
        DishRoleDerivation.proposedRole(for: nonEmptyIngredients)
    }

    /// Whether the soup toggle should be on screen. Soup is a property of a
    /// side dish and of nothing else, so the control does not exist for the
    /// other three roles.
    var showsSoupToggle: Bool { role == .side }

    // MARK: Allergens

    /// What the ingredient names imply on their own, before the user's edits.
    var derivedAllergens: Set<String> {
        AllergenTable.allergens(for: nonEmptyIngredients)
    }

    /// The set that will actually be saved: derived, minus what the user
    /// cleared, plus what the user added.
    var effectiveAllergens: Set<String> {
        derivedAllergens.subtracting(userRemoved).union(userAdded)
    }

    /// Records an explicit tap, in whichever direction it goes.
    mutating func toggleAllergen(_ allergen: String) {
        if effectiveAllergens.contains(allergen) {
            userAdded.remove(allergen)
            if derivedAllergens.contains(allergen) { userRemoved.insert(allergen) }
        } else {
            userRemoved.remove(allergen)
            if !derivedAllergens.contains(allergen) { userAdded.insert(allergen) }
        }
    }

    /// Which ingredient names caused each derived allergen, so the screen can
    /// tell the user *why* a chip is pre-ticked rather than asking them to
    /// trust it. Names are in the order they appear in the recipe.
    func sourcesByAllergen() -> [String: [String]] {
        var sources: [String: [String]] = [:]
        for ingredient in nonEmptyIngredients {
            for allergen in AllergenTable.allergens(forIngredientNamed: ingredient.name).sorted() {
                sources[allergen, default: []].append(ingredient.name)
            }
        }
        return sources
    }

    // MARK: Validation

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Ingredients with an actual name — blank rows are scratch space, not data.
    var nonEmptyIngredients: [Ingredient] {
        ingredients.compactMap { $0.asIngredient() }
    }

    var nonEmptyInstructions: [String] {
        instructions
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The minimum for a recipe that can be cooked from and shopped for: a
    /// name, a cuisine, at least one meal type, and at least one ingredient.
    /// Steps are encouraged but not required — plenty of real recipes are a
    /// list of things thrown in a pan.
    var isSaveable: Bool {
        !trimmedName.isEmpty
            && !trimmedCuisine.isEmpty
            && !mealTypes.isEmpty
            && !nonEmptyIngredients.isEmpty
            && role != nil
    }

    /// Trimmed for the same reason the name is: a value that is only
    /// whitespace is not a value. Unreachable while cuisine comes from the
    /// catalog-backed picker, but this is the one required string that was
    /// checked raw, and it stops being unreachable the moment the cuisine
    /// arrives from anywhere else (free text, a restored file, an import).
    var trimmedCuisine: String { cuisine.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The one-line reason `isSaveable` is false, shown under the save button.
    ///
    /// Role comes LAST, after ingredients, because a proposal needs ingredients
    /// to derive from — asking for a dish type before there is anything to
    /// propose from would be asking the user to do the form's job. The
    /// consequence, recorded rather than hidden: in the running app this
    /// message is very hard to reach, because any draft with an ingredient also
    /// produces a proposal that fills the field. It guards the model, not the
    /// user. That is still the right shape — the alternative, making role a
    /// computed fallback that can never be nil, would make "required" a claim
    /// with nothing behind it.
    var validationMessage: String? {
        if trimmedName.isEmpty { return String(localized: "Give your recipe a name.") }
        if trimmedCuisine.isEmpty { return String(localized: "Pick a cuisine.") }
        if mealTypes.isEmpty { return String(localized: "Pick at least one meal type.") }
        if nonEmptyIngredients.isEmpty { return String(localized: "Add at least one ingredient.") }
        if role == nil { return String(localized: "Pick a dish type.") }
        return nil
    }

    // MARK: Conversion

    /// Builds the saveable `Recipe`. `regions` is looked up from the catalog
    /// so a user recipe carries the same region tag as every built-in recipe
    /// of that cuisine — nothing new is invented. Nutrition is all-nil, which
    /// is exactly what the bundled data holds today.
    func makeRecipe(catalog: CuisineCatalog) -> Recipe {
        Recipe(
            id: id,
            name: trimmedName,
            cuisine: trimmedCuisine,
            regions: catalog.regions
                .filter { $0.cuisines.contains { $0.name == trimmedCuisine } }
                .map(\.name),
            mealTypes: PlanGenerator.mealTypes.filter { mealTypes.contains($0) },
            tags: [],
            allergens: effectiveAllergens.sorted(),
            baseServings: baseServings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            ingredients: nonEmptyIngredients,
            instructions: nonEmptyInstructions,
            nutrition: Nutrition(calories: nil, protein: nil, carbs: nil, fat: nil),
            // Save is gated on `role != nil`, so the fallback is unreachable
            // through the form. It stays as a fallback rather than a `!`
            // because a crash is never the right answer to a draft that got
            // here another way, and `.unassigned` is exactly what the rest of
            // the app already knows how to survive.
            role: role ?? .unassigned,
            // Only a side can be a soup. Enforced here rather than trusted from
            // the draft, so picking Side, ticking Soup, then switching to Main
            // cannot save a flag that contradicts the role.
            isSoup: role == .side && isSoup
            // isUniversal is deliberately NOT set. It says a dish crosses
            // cuisines, which is a claim about the whole corpus that no single
            // author is in a position to make, so it is not user-settable and
            // stays at its default of false.
        )
    }
}

/// One editable ingredient row. Quantity stays a string while typing so
/// "0." and "" are representable; it becomes a `Double?` only on conversion.
struct IngredientDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var quantity: String = ""
    /// nil = no unit, which is how the data models "to taste" items.
    var unit: String?
    var preparation: String = ""

    init() {}

    init(_ ingredient: Ingredient) {
        name = ingredient.name
        quantity = ingredient.quantity.map(Self.format(_:)) ?? ""
        unit = ingredient.unit
        preparation = ingredient.preparation ?? ""
    }

    /// nil when the row has no name — a blank row is discarded, not an error.
    func asIngredient() -> Ingredient? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedPreparation = preparation.trimmingCharacters(in: .whitespacesAndNewlines)
        return Ingredient(
            name: trimmedName,
            quantity: Double(quantity.replacingOccurrences(of: ",", with: ".")),
            unit: unit,
            preparation: trimmedPreparation.isEmpty ? nil : trimmedPreparation,
            // User recipes don't ask for a grocery aisle. "other" is already a
            // real category in the bundled data, so the grocery list groups
            // these under a section it already knows how to render.
            category: "other"
        )
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// One editable instruction step. Wrapped in a type with a stable id so
/// SwiftUI's ForEach doesn't reorder text fields as the list is edited.
struct InstructionDraft: Identifiable {
    let id = UUID()
    var text: String = ""

    init() {}
    init(text: String) { self.text = text }
}
