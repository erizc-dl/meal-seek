//
//  CuisineCatalog.swift
//  Meal Seek
//
//  The region → cuisine mapping, derived at runtime from the loaded recipe
//  database — nothing here is hardcoded, so new cuisines in the JSON appear
//  automatically. A handful of legacy recipes carry two region tags; each
//  cuisine is grouped under its majority region so every cuisine appears in
//  exactly one group and the group counts sum to the full database.
//

import Foundation

struct CuisineCatalog {
    struct Cuisine: Identifiable {
        let name: String
        let recipeCount: Int
        var id: String { name }
    }

    struct Region: Identifiable {
        let name: String
        /// Alphabetical for stable, predictable display order.
        let cuisines: [Cuisine]
        var id: String { name }

        var recipeCount: Int {
            cuisines.reduce(0) { $0 + $1.recipeCount }
        }
    }

    /// Display order: the three known regions first, any future region after,
    /// alphabetically.
    let regions: [Region]

    /// Every cuisine name in the database.
    var allCuisineNames: Set<String> {
        Set(regions.flatMap { $0.cuisines.map(\.name) })
    }

    /// The cuisines grouped under the given regions — how a legacy
    /// region-level selection expands to today's per-cuisine one.
    func cuisineNames(inRegions names: Set<String>) -> Set<String> {
        Set(regions.filter { names.contains($0.name) }
            .flatMap { $0.cuisines.map(\.name) })
    }

    private static let preferredRegionOrder = ["Americas", "European", "Asian"]

    init(recipes: [Recipe]) {
        var recipeCounts: [String: Int] = [:]
        var regionVotes: [String: [String: Int]] = [:]
        for recipe in recipes {
            recipeCounts[recipe.cuisine, default: 0] += 1
            for region in recipe.regions {
                regionVotes[recipe.cuisine, default: [:]][region, default: 0] += 1
            }
        }

        // Majority region per cuisine; ties break alphabetically so the
        // grouping is deterministic run to run.
        var cuisinesByRegion: [String: [Cuisine]] = [:]
        for (cuisine, votes) in regionVotes {
            guard let region = votes.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).first?.key else { continue }
            cuisinesByRegion[region, default: []].append(
                Cuisine(name: cuisine, recipeCount: recipeCounts[cuisine] ?? 0)
            )
        }

        let orderedNames = cuisinesByRegion.keys.sorted { lhs, rhs in
            let li = Self.preferredRegionOrder.firstIndex(of: lhs) ?? .max
            let ri = Self.preferredRegionOrder.firstIndex(of: rhs) ?? .max
            return li == ri ? lhs < rhs : li < ri
        }
        regions = orderedNames.map { name in
            Region(name: name, cuisines: cuisinesByRegion[name]!.sorted { $0.name < $1.name })
        }
    }
}
