//
//  RecipeTranslationStore.swift
//  Meal Seek
//
//  The one place recipe display strings get localized. It loads ONLY the active
//  app language's translation files — or nothing at all when the app is in
//  English — lazily on first lookup, so translation never sits on the launch
//  critical path. Every lookup falls back to the canonical English string, so a
//  missing file, recipe, ingredient, or step renders English, never blank.
//
//  DISPLAY-ONLY CONTRACT: nothing here may reach generation, grocery
//  consolidation, allergen filtering, or search identity. Those read canonical
//  English off the Recipe model forever; the cross-language identity test
//  (tests/translation-tests.swift) locks that in. This store is consumed at the
//  view layer only, via the `\.recipeTranslations` environment value.
//

import Foundation

final class RecipeTranslationStore {
    /// Active language code ("zh-Hans" / "es"), or nil when the app is in
    /// English (or any unsupported localization) — in which case nothing loads.
    let language: String?

    /// Languages that have translation files. English is intentionally absent:
    /// it is the canonical fallback, not a translation.
    static let supported: Set<String> = ["zh-Hans", "es"]

    private struct Loaded {
        var recipes: [String: RecipeTranslation] = [:]
        /// Union of every recipe's ingredient map: canonical name → localized.
        /// Used for the grocery list, whose rows aren't tied to one recipe.
        var ingredientIndex: [String: String] = [:]
        var preparations: [String: String] = [:]
        var units: [String: String] = [:]
        /// Spanish-only: gender/number per ingredient and the four inflected
        /// forms per adjectival preparation. Empty for zh-Hans/English.
        var ingredientGrammar: [String: IngredientGrammar] = [:]
        var preparationForms: [String: PreparationForms] = [:]
        /// Total on-disk bytes of the loaded translation files (0 in English).
        var byteCount: Int = 0
    }

    /// Set only by the test initializer; otherwise the bundle is read lazily.
    private let injected: Loaded?

    /// Loaded on first access → off the app-launch critical path.
    private lazy var loaded: Loaded = injected ?? Self.load(language: language)

    /// Production initializer: resolves the active app language and defers all
    /// file I/O until the first lookup.
    init(language: String? = RecipeTranslationStore.activeLanguage()) {
        self.language = Self.supported.contains(language ?? "") ? language : nil
        self.injected = nil
    }

    /// Test initializer: inject translations directly, no bundle access.
    init(
        language: String?,
        recipes: [String: RecipeTranslation],
        preparations: [String: String] = [:],
        units: [String: String] = [:],
        ingredientGrammar: [String: IngredientGrammar] = [:],
        preparationForms: [String: PreparationForms] = [:]
    ) {
        self.language = language
        var loaded = Loaded(recipes: recipes, preparations: preparations, units: units,
                            ingredientGrammar: ingredientGrammar,
                            preparationForms: preparationForms)
        for translation in recipes.values {
            for (canonical, localized) in translation.ingredients ?? [:] where !localized.isEmpty {
                loaded.ingredientIndex[canonical] = localized
            }
        }
        self.injected = loaded
    }

    /// The app's resolved localization, honoring the per-app iOS language
    /// setting. "en" — or anything not in `supported` — means load nothing.
    static func activeLanguage() -> String? {
        Bundle.main.preferredLocalizations.first
    }

    /// True when a translation language is active (a file may load).
    var isActive: Bool { language != nil }

    /// On-disk size of the loaded translation files, in bytes (0 in English).
    /// Reported to gauge the runtime memory / bundle impact of the active file.
    var loadedByteCount: Int { isActive ? loaded.byteCount : 0 }

    // MARK: - Lookups (every one falls back to English)

    /// Localized recipe name, or the canonical English name.
    func name(for recipe: Recipe) -> String {
        guard isActive else { return recipe.name }
        return loaded.recipes[recipe.id]?.name?.nonEmpty ?? recipe.name
    }

    /// The locale used to collate display names. When a translation language is
    /// active we collate under *that* language so the order reads correctly to
    /// the person reading it (pinyin order for zh-Hans, es collation for es);
    /// English/inactive falls back to the user's current locale.
    private var collationLocale: Locale {
        guard let language else { return .current }
        return Locale(identifier: language)
    }

    /// Recipes ordered by the name the user actually sees, collated with
    /// `localizedStandardCompare`-equivalent options under the active locale.
    ///
    /// PRESENTATION ONLY: identity, eligibility filtering, and allergen matching
    /// keep reading canonical English off the `Recipe` model. Search may also
    /// match the translated display name; only the on-screen order changes with
    /// the language. In English this reduces to the canonical-name ordering it
    /// replaced.
    func sortedByDisplayName(_ recipes: [Recipe]) -> [Recipe] {
        let locale = collationLocale
        return recipes.sorted { a, b in
            // Options mirror `localizedStandardCompare` (Finder-style: case- and
            // width-insensitive, numeric-aware) but let us pin the locale.
            name(for: a).compare(
                name(for: b),
                options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering],
                range: nil,
                locale: locale
            ) == .orderedAscending
        }
    }

    /// Localized ingredient name within a specific recipe (prefers the recipe's
    /// own entry, then the global index, then the canonical English name).
    func ingredientName(_ canonical: String, in recipeID: String) -> String {
        guard isActive else { return canonical }
        return loaded.recipes[recipeID]?.ingredients?[canonical]?.nonEmpty
            ?? loaded.ingredientIndex[canonical]
            ?? canonical
    }

    /// Localized ingredient name for the grocery list (recipe-independent).
    func groceryIngredientName(_ canonical: String) -> String {
        guard isActive else { return canonical }
        return loaded.ingredientIndex[canonical] ?? canonical
    }

    /// Localized preparation ("diced" → "切丁"), or the English original.
    func preparation(_ english: String) -> String {
        guard isActive else { return english }
        return loaded.preparations[english]?.nonEmpty ?? english
    }

    /// Localized word-unit ("tbsp" → "汤匙"). Symbol units (g/kg/ml/l) and any
    /// unmapped unit return unchanged.
    func unit(_ english: String) -> String {
        guard isActive else { return english }
        return loaded.units[english]?.nonEmpty ?? english
    }

    /// Localized instruction step. `english` is the canonical step passed in so
    /// the fallback needs no second lookup.
    func instruction(at index: Int, in recipeID: String, english: String) -> String {
        guard isActive else { return english }
        guard let steps = loaded.recipes[recipeID]?.instructions,
              index < steps.count, let step = steps[index]?.nonEmpty else { return english }
        return step
    }

    /// A fully localized ingredient line. For most languages this mirrors
    /// `Ingredient.displayText` exactly, swapping name, word-unit, and
    /// preparation for translations while leaving quantities and symbol units
    /// untouched. Spanish takes a dedicated path (`spanishLine`) because its
    /// grammar — adjective agreement and the partitive "de" — can't be expressed
    /// by string substitution alone.
    func ingredientLine(_ ingredient: Ingredient, in recipeID: String) -> String {
        if language == "es" {
            return spanishLine(ingredient, in: recipeID)
        }
        return ingredient.displayText(
            nameOverride: ingredientName(ingredient.name, in: recipeID),
            unitOverride: ingredient.unit.map { unit($0) },
            preparationOverride: ingredient.preparation.map { preparation($0) }
        )
    }

    // MARK: - Spanish ingredient-line assembly

    /// Symbol units are international and never localized or pluralized.
    private static let symbolUnits: Set<String> = ["g", "kg", "ml", "l"]

    /// Formats a quantity dropping a trailing ".0" (600.0 → "600", 0.5 → "0.5"),
    /// matching `Ingredient.formatQuantity` so numerals render identically.
    private static func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Assembles a Spanish ingredient line with two rules a flat glossary can't
    /// carry:
    ///   • **Partitive "de":** measure/container units take it ("500 g de
    ///     harina", "3 dientes de ajo"); a bare count does not ("2 huevos").
    ///   • **Agreement:** an adjectival preparation agrees in gender and number
    ///     with the ingredient ("cebolla, picada" vs "ajo, picado").
    /// Falls back gracefully when grammar data is absent (defaults to masculine,
    /// count-driven number), so a partial es file never crashes or blanks.
    private func spanishLine(_ ingredient: Ingredient, in recipeID: String) -> String {
        var name = ingredientName(ingredient.name, in: recipeID)
        // Drop the redundant "en lata" when the ingredient is bought by the can:
        // "1 lata de garbanzos en lata" → "1 lata de garbanzos". The English
        // source is identically redundant ("canned X in a can"); that's a
        // source-data bug fixed separately, but the display shouldn't echo it.
        if ingredient.unit == "can", name.hasSuffix(" en lata") {
            name = String(name.dropLast(" en lata".count))
        }
        let grammar = loaded.ingredientGrammar[ingredient.name]
        let gender = grammar?.gender ?? "m"
        let unit = ingredient.unit
        let isBareCount = unit == nil || unit == "piece"
        let countIsPlural = (ingredient.quantity ?? 0) > 1
        // A preparation agrees plural when the ingredient is inherently plural
        // (frijoles) or a bare count above one (2 huevos).
        let prepIsPlural = grammar?.number == "p" || (isBareCount && countIsPlural)

        var pieces: [String] = []
        if let quantity = ingredient.quantity {
            pieces.append(Self.formatQuantity(quantity))
        }

        if let unit, !isBareCount {
            // Measure/container unit: localize + pluralize the unit word, then
            // the partitive "de", then the ingredient in its dictionary form.
            pieces.append(spanishUnitWord(unit, plural: countIsPlural))
            pieces.append("de")
            pieces.append(name)
        } else {
            // Bare count: drop the unit word; pluralize the noun itself by count.
            pieces.append(isBareCount && countIsPlural ? Self.spanishPluralize(name) : name)
        }
        var line = pieces.joined(separator: " ")

        if let prep = ingredient.preparation, !prep.isEmpty {
            let rendered: String
            if let forms = loaded.preparationForms[prep] {
                rendered = forms.form(gender: gender, plural: prepIsPlural)
            } else {
                // Invariable prepositional phrase ("en cubitos", "al gusto").
                rendered = loaded.preparations[prep]?.nonEmpty ?? prep
            }
            line += ", \(rendered)"
        }
        return line
    }

    /// A localized, count-aware Spanish unit word. Symbol units (g/ml/…) and
    /// abbreviations (cda./cdta.) never change; full words pluralize with "s"
    /// ("diente"→"dientes", "lata"→"latas").
    private func spanishUnitWord(_ english: String, plural: Bool) -> String {
        let base = unit(english)
        guard plural, !Self.symbolUnits.contains(english), !base.hasSuffix(".") else {
            return base
        }
        return base + "s"
    }

    /// Regular Spanish pluralization of a display noun phrase. Only the head
    /// segment (before " de ") inflects; a trailing "de …" complement stays
    /// singular ("tortilla de maíz" → "tortillas de maíz"). A heuristic sized for
    /// the bare-count foods in this corpus, not a full morphology engine.
    static func spanishPluralize(_ phrase: String) -> String {
        let segments = phrase.components(separatedBy: " de ")
        let head = segments[0].split(separator: " ").map { pluralizeWord(String($0)) }
        var result = head.joined(separator: " ")
        if segments.count > 1 {
            result += " de " + segments.dropFirst().joined(separator: " de ")
        }
        return result
    }

    private static func pluralizeWord(_ word: String) -> String {
        if word.hasSuffix("ón") { return String(word.dropLast(2)) + "ones" } // limón→limones
        guard let last = word.last else { return word }
        if "aeiouáéó".contains(last) { return word + "s" }
        if "íú".contains(last) { return word + "es" } // ají→ajíes
        if last == "z" { return String(word.dropLast()) + "ces" } // nuez→nueces
        if last == "s" { return word } // already plural / invariable
        return word + "es" // pan→panes
    }

    /// The grocery row's trailing quantity, mirroring `GroceryItem.displayQuantity`
    /// but with a localized word-unit. Returns nil for to-taste rows.
    func groceryQuantity(_ item: GroceryItem) -> String? {
        guard let quantity = item.quantity else { return nil }
        let number = quantity == quantity.rounded() ? String(Int(quantity)) : String(quantity)
        // The unit WORD localizes ("can" → "lata" → "罐"); the weight suffix is
        // digits and symbols only, so it is identical in every language.
        let suffix = GroceryItem.weightSuffix(item.approximateGrams)
        guard let unit = item.unit, unit != "piece" else { return number + suffix }
        return "\(number) \(self.unit(unit))\(suffix)"
    }

    // MARK: - Loading

    private static func load(language: String?) -> Loaded {
        guard let language else { return Loaded() }
        var result = Loaded()

        if let file: RecipeTranslationFile = decode("recipes.\(language)", into: &result.byteCount) {
            result.recipes = file.recipes
            for translation in file.recipes.values {
                for (canonical, localized) in translation.ingredients ?? [:] where !localized.isEmpty {
                    result.ingredientIndex[canonical] = localized
                }
            }
        }

        if let file: RecipeTermsFile = decode("recipe-terms.\(language)", into: &result.byteCount) {
            result.preparations = file.preparations
            result.units = file.units
            result.ingredientGrammar = file.ingredientGrammar ?? [:]
            result.preparationForms = file.preparationForms ?? [:]
        }

        return result
    }

    /// Decodes a bundled JSON resource, adding its byte size to `byteCount`.
    /// A missing or malformed file returns nil — the store simply falls back to
    /// English rather than failing (translations are never load-bearing).
    private static func decode<T: Decodable>(_ resource: String, into byteCount: inout Int) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            print("⚠️ RecipeTranslationStore: \(resource).json present but failed to decode; using English.")
            return nil
        }
        byteCount += data.count
        return decoded
    }
}

private extension String {
    /// nil when empty, so an empty-string translation falls back to English.
    var nonEmpty: String? { isEmpty ? nil : self }
}
