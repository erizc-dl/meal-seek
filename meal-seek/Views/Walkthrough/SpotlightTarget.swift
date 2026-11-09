//
//  SpotlightTarget.swift
//  Meal Seek
//
//  How a view says "the walkthrough can point at me".
//
//  The mechanism is the standard declarative one: each target attaches its
//  bounds as an `Anchor<CGRect>` to a preference, and ONE ancestor resolves
//  every anchor at once through a `GeometryReader`. That is what makes this work
//  across navigation stacks, scroll views, and safe areas without any of them
//  knowing the walkthrough exists -- the anchor is resolved in the resolver's
//  coordinate space, so a target inside a scrolled card reports where it
//  actually is on screen, not where it is in its own container.
//

import SwiftUI

/// One registered target: where it is, and what shape it is.
///
/// Bounds and radius travel together in ONE preference so the overlay resolves
/// a single value. Splitting them across two keys forces the resolver to nest
/// two `overlayPreferenceValue` calls and render its content twice.
struct SpotlightRegistration {
    let anchor: Anchor<CGRect>
    /// The target's own corner radius; the cutout adds its padding on top.
    let cornerRadius: CGFloat
}

/// Collects every registered target's bounds for the current frame.
///
/// A dictionary rather than a single value because the resolver runs once for
/// the whole screen: several targets may be registered at the same moment (a
/// step's target plus targets on other tabs that happen to be alive), and the
/// overlay picks out the one it needs.
struct SpotlightAnchorKey: PreferenceKey {
    static let defaultValue: [WalkthroughStep: SpotlightRegistration] = [:]

    static func reduce(
        value: inout [WalkthroughStep: SpotlightRegistration],
        nextValue: () -> [WalkthroughStep: SpotlightRegistration]
    ) {
        // Last writer wins. Two views claiming one step is a bug, but the
        // later one is the more recently laid out, so it is the better guess.
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Registers this view as the spotlight target for `step` -- the rect the
    /// user must be able to TAP.
    ///
    /// INERT WHEN NOT RUNNING. The modifier is always in the chain -- which
    /// keeps view identity stable, so attaching it can never reset a
    /// TextField's focus or a ScrollView's offset -- but it publishes an EMPTY
    /// dictionary unless the walkthrough is actually running, and the root
    /// installs no overlay to read it. `anchorPreference` reports geometry; it
    /// never changes it.
    func spotlightTarget(_ step: WalkthroughStep, cornerRadius: CGFloat = 12) -> some View {
        modifier(SpotlightTargetModifier(step: step, cornerRadius: cornerRadius))
    }

    /// Optional form, for a view that is only SOMETIMES the target -- the first
    /// dish row of the first meal card, the first unbought grocery item. Passing
    /// nil registers nothing while keeping the modifier in the chain, so view
    /// identity does not change as the answer flips.
    func spotlightTarget(_ step: WalkthroughStep?, cornerRadius: CGFloat = 12) -> some View {
        modifier(SpotlightTargetModifier(step: step, cornerRadius: cornerRadius))
    }

    /// Narrows the CUTOUT to a sub-part of the target, without narrowing what
    /// the user can tap.
    ///
    /// These are two different rects and the engine used to conflate them. A
    /// grocery row is the tap target, but pointing at the whole row says
    /// "somewhere here"; pointing at the checkbox says what to do. So the
    /// blocking rects are built around the TAP rect and the visible hole is
    /// drawn around this one. Defaults to the tap rect when absent.
    func spotlightCutout(_ step: WalkthroughStep?, cornerRadius: CGFloat = 12) -> some View {
        modifier(SpotlightCutoutModifier(step: step, cornerRadius: cornerRadius))
    }
}

/// The narrowed visual rect for a step, when one is registered.
struct SpotlightVisualKey: PreferenceKey {
    static let defaultValue: [WalkthroughStep: SpotlightRegistration] = [:]

    static func reduce(
        value: inout [WalkthroughStep: SpotlightRegistration],
        nextValue: () -> [WalkthroughStep: SpotlightRegistration]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct SpotlightCutoutModifier: ViewModifier {
    let step: WalkthroughStep?
    let cornerRadius: CGFloat

    @Environment(\.walkthrough) private var walkthrough

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: SpotlightVisualKey.self, value: .bounds) { anchor in
                guard walkthrough.isRunning, let step else { return [:] }
                return [step: SpotlightRegistration(anchor: anchor, cornerRadius: cornerRadius)]
            }
    }
}

private struct SpotlightTargetModifier: ViewModifier {
    let step: WalkthroughStep?
    let cornerRadius: CGFloat

    @Environment(\.walkthrough) private var walkthrough
    @Environment(\.spotlightScreenIsVisible) private var screenIsVisible

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { anchor in
                // The whole cost of a registered target while the walkthrough
                // is off: two Bool reads and an empty dictionary.
                guard walkthrough.isRunning, screenIsVisible, let step else { return [:] }
                return [step: SpotlightRegistration(anchor: anchor, cornerRadius: cornerRadius)]
            }
    }
}

// MARK: Screen visibility

extension EnvironmentValues {
    /// Whether the screen hosting a target is the one actually on top.
    ///
    /// Defaults to true so a view outside any marked screen still registers.
    @Entry var spotlightScreenIsVisible = true
}

extension View {
    /// Marks a screen's content, so targets inside it stop registering when the
    /// screen is covered.
    ///
    /// This is the ONLY signal available for the covered-by-push case. A
    /// `NavigationStack` push COVERS the source, it does not remove it: the
    /// source stays in the hierarchy, keeps publishing its anchor, and that
    /// anchor keeps resolving to a perfectly valid rect. That is what put a
    /// spotlight over three pantry rows while the card read "All your recipes
    /// live here".
    ///
    /// `onDisappear` on push is the imperfect part -- it is not guaranteed to
    /// fire for a covered-but-retained view on every iOS version. The overlay's
    /// viewport check is the backstop: between them, a target that is neither
    /// on-screen nor on the visible screen renders no cutout at all.
    func spotlightScreen() -> some View {
        modifier(SpotlightScreenModifier())
    }
}

private struct SpotlightScreenModifier: ViewModifier {
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .environment(\.spotlightScreenIsVisible, isVisible)
    }
}
