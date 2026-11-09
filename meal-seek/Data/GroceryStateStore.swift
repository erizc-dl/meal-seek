//
//  GroceryStateStore.swift
//  Meal Seek
//
//  Persists which grocery items have been bought, per week, as a JSON file in
//  the Documents directory. No UserDefaults, SwiftData, or Core Data.
//

import Foundation

@Observable
final class GroceryStateStore {
    /// Checked-off grocery row IDs per week, keyed by the week's Monday. A
    /// row ID is the bare ingredient name, or "name#family" when incompatible
    /// unit families split an ingredient into several rows — see GroceryItem.
    /// (The persisted JSON key remains "boughtNames" for file compatibility;
    /// bare-name entries saved before the split scheme still match their rows.)
    private(set) var boughtByWeek: [Date: Set<String>] = [:]

    private static let fileName = "grocerystate.json"

    /// On-disk representation: one entry per week, same array-of-weeks shape
    /// as weekplans.json.
    private struct WeekBoughtState: Codable {
        let weekStartDate: Date
        let boughtNames: Set<String>
    }

    init() {
        boughtByWeek = Self.load()
    }

    func boughtNames(for weekStart: Date) -> Set<String> {
        boughtByWeek[Calendar.current.mondayOfWeek(containing: weekStart)] ?? []
    }

    func setBought(_ name: String, bought: Bool, for weekStart: Date) {
        let key = Calendar.current.mondayOfWeek(containing: weekStart)
        var names = boughtByWeek[key] ?? []
        if bought {
            names.insert(name)
        } else {
            names.remove(name)
        }
        boughtByWeek[key] = names
        persist()
    }

    /// "Clear" — returns every bought item to its aisle for this week.
    func clear(for weekStart: Date) {
        boughtByWeek[Calendar.current.mondayOfWeek(containing: weekStart)] = []
        persist()
    }

    /// Reconciles the bought set against the week's current grocery list:
    /// keeps checked names that are still on the list, drops ones that no
    /// longer appear (e.g. after the week was regenerated). Never wipes.
    func retainOnly(names availableNames: Set<String>, for weekStart: Date) {
        let key = Calendar.current.mondayOfWeek(containing: weekStart)
        guard let bought = boughtByWeek[key] else { return }
        let retained = bought.intersection(availableNames)
        guard retained != bought else { return }
        boughtByWeek[key] = retained
        persist()
    }

    /// Absolute URL of the state file in Documents, or nil if it can't be resolved.
    private static func fileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ GroceryStateStore: could not locate the Documents directory.")
            return nil
        }
        return documents.appendingPathComponent(fileName)
    }

    private static func load() -> [Date: Set<String>] {
        guard let url = fileURL() else { return [:] }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ℹ️ GroceryStateStore: no grocery state file yet — starting empty.")
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode([WeekBoughtState].self, from: data)
            var byWeek: [Date: Set<String>] = [:]
            for state in stored {
                byWeek[Calendar.current.mondayOfWeek(containing: state.weekStartDate)] = state.boughtNames
            }
            print("✅ GroceryStateStore: loaded bought state for \(byWeek.count) week(s) from \(url.path)")
            return byWeek
        } catch {
            print("❌ GroceryStateStore: failed to read \(url.path) — \(error.localizedDescription). Starting empty.")
            return [:]
        }
    }

    /// Re-reads all weeks' bought state from disk. Used after a data restore so
    /// the grocery list reflects the restored file without a relaunch.
    func reload() {
        boughtByWeek = Self.load()
    }

    /// Replaces all bought state with `newState` and persists in one step,
    /// re-keying each week through the Monday helper exactly as load() does.
    /// Throws on write failure so a restore can report a partial failure. Note
    /// the values are grocery row-ids (name or "name#family"), never recipe ids.
    func restore(_ newState: [Date: Set<String>]) throws {
        guard let url = Self.fileURL() else { throw BackupError.documentsUnavailable }
        var rekeyed: [Date: Set<String>] = [:]
        for (week, names) in newState {
            rekeyed[Calendar.current.mondayOfWeek(containing: week)] = names
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stored = rekeyed.keys.sorted().compactMap { key in
            rekeyed[key].map { WeekBoughtState(weekStartDate: key, boughtNames: $0) }
        }
        let data = try encoder.encode(stored)
        try data.write(to: url, options: .atomic)
        boughtByWeek = rekeyed
    }

    /// Persist all weeks to disk. Errors are reported, never fatal.
    private func persist() {
        guard let url = Self.fileURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let stored = boughtByWeek.keys.sorted().compactMap { key in
                boughtByWeek[key].map { WeekBoughtState(weekStartDate: key, boughtNames: $0) }
            }
            let data = try encoder.encode(stored)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ GroceryStateStore: failed to save grocery state — \(error.localizedDescription)")
        }
    }
}
