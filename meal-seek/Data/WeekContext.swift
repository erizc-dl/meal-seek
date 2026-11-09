//
//  WeekContext.swift
//  Meal Seek
//
//  The day (and therefore week) currently displayed on Home, shared so the
//  Grocery tab always builds its list for the same week the user is viewing.
//

import Foundation

@Observable
final class WeekContext {
    /// The day selected on the Home screen, normalized to local midnight.
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// The Monday of the displayed week.
    var displayedWeekStart: Date {
        Calendar.current.mondayOfWeek(containing: selectedDate)
    }
}
