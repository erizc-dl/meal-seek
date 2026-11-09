//
//  DiagnosticReport.swift
//  Meal Seek
//
//  Assembles the plain-text diagnostic a tester attaches when they tap "Report
//  this problem" on a generation-error screen. Keeping the format here means
//  every current and future error surface produces the same shape, and the
//  privacy contract lives in one place: device/app context plus the settings
//  that drove the failure — never recipe content, and no personal identifier
//  (the kitchen's display name is deliberately excluded).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct DiagnosticReport {
    /// Device/app context. Injected so the report is pure and unit-testable;
    /// `.current()` gathers the real values on-device.
    struct Environment: Equatable {
        let appVersion: String
        let buildNumber: String
        let systemName: String
        let systemVersion: String
        let deviceModel: String

        static func current() -> Environment {
            let info = Bundle.main.infoDictionary
            #if canImport(UIKit)
            let device = UIDevice.current
            return Environment(
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                buildNumber: info?["CFBundleVersion"] as? String ?? "?",
                systemName: device.systemName,
                systemVersion: device.systemVersion,
                deviceModel: modelIdentifier()
            )
            #else
            return Environment(
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                buildNumber: info?["CFBundleVersion"] as? String ?? "?",
                systemName: "iOS",
                systemVersion: "?",
                deviceModel: modelIdentifier()
            )
            #endif
        }

        /// The hardware identifier (e.g. "iPhone17,1"); `UIDevice.model` only
        /// ever returns the generic "iPhone", so read it from `uname`.
        private static func modelIdentifier() -> String {
            var systemInfo = utsname()
            uname(&systemInfo)
            let identifier = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
                let bytes = raw.prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
            return identifier.isEmpty ? "?" : identifier
        }
    }

    let error: WeekGenerationError
    /// Recipes that survived the allergen + cuisine filter — what generation
    /// actually had to work with.
    let recipesPassingFilter: Int
    let cuisines: [String]
    let allergens: [String]
    let servings: Int
    let environment: Environment

    /// Builds a report for a generation failure, deriving the passed-filter
    /// count and the active settings from the same inputs generation used. No
    /// recipe content and no display name ever leave via this path.
    static func forGenerationFailure(
        error: WeekGenerationError,
        recipes: [Recipe],
        preferences: UserPreferences,
        environment: Environment = .current()
    ) -> DiagnosticReport {
        let passing = RecipeFilter.inCuisines(
            RecipeFilter.allergenSafe(recipes, allergens: preferences.allergens),
            cuisines: preferences.cuisines
        ).count
        return DiagnosticReport(
            error: error,
            recipesPassingFilter: passing,
            cuisines: preferences.cuisines.sorted(),
            allergens: preferences.allergens.sorted(),
            servings: preferences.householdSize,
            environment: environment
        )
    }

    /// The shareable plain text. Order is fixed so reports are easy to scan.
    var text: String {
        """
        Meal Seek week-generation diagnostic

        Error: \(error.diagnosticDescription)
        Recipes passing filter: \(recipesPassingFilter)
        Cuisines: \(listOrNone(cuisines))
        Allergens: \(listOrNone(allergens))
        Servings: \(servings)

        App version: \(environment.appVersion)
        Build: \(environment.buildNumber)
        \(environment.systemName) \(environment.systemVersion)
        Device: \(environment.deviceModel)
        """
    }

    private func listOrNone(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }
}
