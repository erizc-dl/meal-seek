//
//  AppTab.swift
//  Meal Seek
//
//  The three root tabs.
//
//  Extracted from RootView so the walkthrough can name a destination tab
//  without depending on the whole view layer. That dependency is what made the
//  coordinator untestable: a harness cannot compile `RootView` without dragging
//  in Home, Grocery, Account and everything they touch. `RootView.Tab` still
//  resolves, via a typealias, so no call site changed.
//

enum AppTab: Hashable, CaseIterable {
    case home, grocery, account
}
