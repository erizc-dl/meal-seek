//
//  FeedbackLogger.swift
//  Meal Seek
//
//  Append-only log of meal-swap signals to feedback.json in the Documents
//  directory, same JSON-file pattern as the other stores. Write-only today:
//  nothing reads it. Failures are silent by design — logging must never
//  block or break a swap, so errors go to the console and the event is
//  dropped.
//

import Foundation

enum FeedbackLogger {
    private static let fileName = "feedback.json"

    static func log(_ event: FeedbackEvent) {
        log([event])
    }

    /// Appends events to feedback.json. Never throws, never crashes.
    ///
    /// Called only from user-initiated swap handlers. Never call from a
    /// mutator or from generation code — a mutator cannot know whether a
    /// human or an algorithm invoked it; only the call site knows intent.
    static func log(_ events: [FeedbackEvent]) {
        guard !events.isEmpty, let url = fileURL() else { return }
        var all = loadExisting(from: url)
        all.append(contentsOf: events)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(all)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ FeedbackLogger: failed to save feedback — \(error.localizedDescription)")
        }
    }

    private static func loadExisting(from url: URL) -> [FeedbackEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([FeedbackEvent].self, from: data)
        } catch {
            print("❌ FeedbackLogger: failed to read \(url.path) — \(error.localizedDescription). Starting a fresh log.")
            return []
        }
    }

    private static func fileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ FeedbackLogger: could not locate the Documents directory.")
            return nil
        }
        return documents.appendingPathComponent(fileName)
    }
}
