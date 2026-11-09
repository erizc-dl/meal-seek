//
//  WalkthroughOverlay.swift
//  Meal Seek
//
//  Resolves every registered target's anchor and draws the scrim, the cutout,
//  and the coach card for the current step.
//
//  Hosted once, at the root, ABOVE the TabView -- so it survives a tab switch
//  and sits over both tabs and anything their navigation stacks have pushed.
//

import SwiftUI

/// Geometry constants for the spotlight.
enum SpotlightMetrics {
    /// Breathing room between the target's own bounds and the cutout edge.
    static let cutoutPadding: CGFloat = 6
    /// Gap between the cutout and the coach card.
    static let cardGap: CGFloat = 12
    /// How far the card stays clear of the screen edges.
    static let screenMargin: CGFloat = 20
    /// The move between two steps' cutouts.
    static let transition = Animation.easeInOut(duration: 0.25)
}

extension View {
    /// Installs the walkthrough overlay above this view.
    ///
    /// Attaches NOTHING when the walkthrough is not running: no scrim, no
    /// preference resolution, no extra view in the hierarchy.
    func walkthroughOverlay(_ coordinator: WalkthroughCoordinator) -> some View {
        modifier(WalkthroughOverlayModifier(coordinator: coordinator))
    }
}

private struct WalkthroughOverlayModifier: ViewModifier {
    @Bindable var coordinator: WalkthroughCoordinator

    func body(content: Content) -> some View {
        if coordinator.isRunning {
            content
                .overlayPreferenceValue(SpotlightAnchorKey.self) { registrations in
                    // A second, OPTIONAL preference carrying a narrower visual
                    // rect. Read as an overlay on a hidden copy so both keys
                    // resolve in the same pass without the content rendering
                    // twice for real.
                    Color.clear.overlayPreferenceValue(SpotlightVisualKey.self) { visuals in
                        GeometryReader { proxy in
                            resolved(registrations: registrations, visuals: visuals, proxy: proxy)
                        }
                        .ignoresSafeArea()
                    }
                }
        } else {
            content
        }
    }

    /// The overlay for the current step, or nothing at all when its target is
    /// not on screen.
    ///
    /// Hiding rather than guessing is deliberate. If the user has navigated
    /// somewhere the step's target does not exist -- pushed a recipe, switched
    /// tabs early -- there is no rect to point at, and a spotlight on a stale
    /// rect would be actively misleading. The overlay reappears by itself when
    /// they come back, because the target starts publishing again.
    @ViewBuilder
    private func resolved(
        registrations: [WalkthroughStep: SpotlightRegistration],
        visuals: [WalkthroughStep: SpotlightRegistration],
        proxy: GeometryProxy
    ) -> some View {
        if let step = coordinator.step {
            switch placement(for: step, registrations: registrations, proxy: proxy) {
            case .spotlight(let rect, let cornerRadius):
                // What the user may TAP.
                let tappable = rect.insetBy(
                    dx: -SpotlightMetrics.cutoutPadding,
                    dy: -SpotlightMetrics.cutoutPadding
                )
                // What is DRAWN as the hole -- narrower when the step registered
                // a tighter visual rect. Never wider than the tappable region,
                // or the dim would promise a target the scrim then blocks.
                let visual = visuals[step].map { proxy[$0.anchor] }
                let hole = (visual ?? rect).insetBy(
                    dx: -SpotlightMetrics.cutoutPadding,
                    dy: -SpotlightMetrics.cutoutPadding
                )
                let radius = (visuals[step]?.cornerRadius ?? cornerRadius) + SpotlightMetrics.cutoutPadding
                ZStack(alignment: .topLeading) {
                    scrim(visualHole: hole, radius: radius, tappable: tappable, in: proxy.size)
                    card(for: step, hole: hole, in: proxy.size)
                }
                .animation(SpotlightMetrics.transition, value: hole)

            case .cardOnly:
                // NON-BLOCKING, deliberately. A full scrim with no hole would
                // swallow every tap and every scroll, which traps the user: the
                // two ways to reach an absent target are to scroll to it or to
                // navigate back to it, and blocking forbids both. They would be
                // left with "Skip" as the only working control -- the
                // walkthrough breaking the app it is teaching.
                //
                // So the dim stays (the step is still in progress) but the app
                // underneath keeps working. The cutout and its blockers return
                // by themselves the moment the target does.
                let anchorLine = CGRect(
                    x: proxy.size.width / 2,
                    y: proxy.size.height - TabBarGeometry.bottomMargin - TabBarGeometry.height,
                    width: 0,
                    height: 0
                )
                ZStack(alignment: .topLeading) {
                    Color.walkthroughScrim
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    card(for: step, hole: anchorLine, in: proxy.size)
                }

            }
        }
    }

    /// Whether a resolved rect is somewhere the user could actually act on.
    ///
    /// Requires the target to be MOSTLY visible rather than merely touching the
    /// screen: a row peeking one point above the fold is not something anyone
    /// can be asked to tap.
    static func isUsable(_ rect: CGRect, in size: CGSize) -> Bool {
        WalkthroughOverlayGeometry.isUsable(rect, in: size)
    }

    /// What the overlay can draw for a step.
    private enum Placement {
        /// Point at this rect.
        case spotlight(rect: CGRect, cornerRadius: CGFloat)
        /// Scrim and coach card, NO cutout and NO blocking.
        ///
        /// Used whenever there is no rect worth pointing at: the target is not
        /// registered, it is scrolled out of the viewport, its screen has been
        /// covered by a push, or the tab derivation declined.
        case cardOnly
    }

    /// Where to cut, for either kind of target.
    ///
    /// Most steps point at a view, which published its own bounds. Tab steps
    /// cannot -- see TabBarGeometry -- so their rect is derived from the screen.
    private func placement(
        for step: WalkthroughStep,
        registrations: [WalkthroughStep: SpotlightRegistration],
        proxy: GeometryProxy
    ) -> Placement {
        // Handing off: point at the tab the user needs to visit.
        if coordinator.isHandingOff, let index = step.handoffTabIndex {
            // A tab step ALWAYS shows its card, cutout or not: the instruction
            // is the point, and the tab bar is findable without a spotlight.
            guard let rect = TabBarGeometry.rect(
                for: index,
                of: AppTab.allCases.count,
                in: proxy.size,
                bottomInset: proxy.safeAreaInsets.bottom
            ) else { return .cardOnly }
            return .spotlight(rect: rect, cornerRadius: TabBarGeometry.height / 2)
        }
        // A teaching beat with nothing to point at: card over the plain scrim.
        if step.hasNoSpotlight { return .cardOnly }

        guard let registration = registrations[step] else { return .cardOnly }
        let rect = proxy[registration.anchor]

        // A target is ABSENT in three ways, and all three must render the card
        // alone rather than a cutout: it is not registered (handled above), it
        // is scrolled outside the viewport, or its screen has been covered by a
        // pushed destination (handled by `spotlightScreen`, which stops the
        // registration).
        //
        // Never a stale rect. A hole over content the user cannot act on is
        // worse than no hole, because it asserts something false.
        guard Self.isUsable(rect, in: proxy.size) else { return .cardOnly }
        return .spotlight(rect: rect, cornerRadius: registration.cornerRadius)
    }

    /// The dim, with the target punched out.
    ///
    /// TWO SEPARATE MECHANISMS, deliberately:
    ///
    /// - The VISUAL is one even-odd shape, and is `allowsHitTesting(false)`.
    ///   It is never asked a containment question.
    /// - The HIT BLOCKING is four plain rectangles arranged AROUND the hole, so
    ///   there is simply no view over the target at all.
    ///
    /// They cannot share a mechanism: `contentShape(_:eoFill:)` hit-tests via
    /// `SwiftUI.Path.contains(_:eoFill:)`, which returns `true` inside a hole
    /// made from a rounded rect -- i.e. it reports the hole as solid. Every
    /// cutout here is rounded, so the old single-shape version drew a hole that
    /// could be seen and not tapped. See SpotlightCutout.swift for the measured
    /// truth table.
    ///
    /// Taps OUTSIDE still land on a blocking rect and stop there. No gesture is
    /// attached, so tapping the dim neither advances nor dismisses: someone who
    /// taps expecting dismissal should find that nothing happened, not that they
    /// lost their place.
    private func scrim(visualHole: CGRect, radius: CGFloat, tappable: CGRect, in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            SpotlightCutout(hole: visualHole, radius: radius)
                .fill(Color.walkthroughScrim, style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            // Blockers are built around the TAPPABLE rect, not the visual hole:
            // the dim may be tight around a checkbox while the whole row stays
            // tappable.
            ForEach(Array(Self.blockingRects(around: tappable, in: size).enumerated()), id: \.offset) { _, rect in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
    }

    /// See `WalkthroughOverlayGeometry.blockingRects`.
    static func blockingRects(around hole: CGRect, in size: CGSize) -> [CGRect] {
        WalkthroughOverlayGeometry.blockingRects(around: hole, in: size)
    }


    /// Places the coach card below the cutout, or above it when the cutout is in
    /// the lower half of the screen.
    private func card(for step: WalkthroughStep, hole: CGRect, in size: CGSize) -> some View {
        let placeBelow = hole.midY < size.height / 2
        let width = size.width - SpotlightMetrics.screenMargin * 2

        // Spelled out rather than a ternary: `showsNext ? confirmStep : nil`
        // mixes a method reference with nil and defeats type inference.
        let onNext: (() -> Void)?
        if coordinator.showsNext {
            onNext = { coordinator.confirmStep() }
        } else {
            onNext = nil
        }

        return CoachCard(
            title: step.title,
            message: coordinator.currentMessage ?? step.message,
            stepIndex: step.index,
            stepCount: WalkthroughStep.count,
            onNext: onNext,
            onSkip: { coordinator.skip() }
        )
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        // Measured so the card can be positioned against its own height without
        // the caller guessing it.
        .modifier(CardPlacement(hole: hole, size: size, placeBelow: placeBelow))
    }
}

/// Positions the card relative to the cutout using the card's measured height.
///
/// A separate modifier because the height is only known after layout, and
/// `alignmentGuide` cannot see it -- so the card measures itself, then offsets.
private struct CardPlacement: ViewModifier {
    let hole: CGRect
    let size: CGSize
    let placeBelow: Bool

    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { height = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, new in height = new }
                }
            )
            .offset(x: SpotlightMetrics.screenMargin, y: y)
    }

    private var y: CGFloat {
        let below = hole.maxY + SpotlightMetrics.cardGap
        let above = hole.minY - SpotlightMetrics.cardGap - height
        let unclamped = placeBelow ? below : above
        // Never let the card leave the screen, however extreme the target.
        let lowest = size.height - height - SpotlightMetrics.screenMargin
        return min(max(unclamped, SpotlightMetrics.screenMargin), max(lowest, SpotlightMetrics.screenMargin))
    }
}


/// Scrim geometry, split out so the harness can assert it without building a
/// view. The property that matters -- no blocker overlaps the hole -- is pure
/// arithmetic, and keeping it that way is what makes it testable at all.
enum WalkthroughOverlayGeometry {
    /// A target must have at least this much of its area on screen to be worth
    /// pointing at.
    static let minimumVisibleFraction: CGFloat = 0.75

    /// Whether a resolved rect is usable as a spotlight target.
    static func isUsable(_ rect: CGRect, in size: CGSize) -> Bool {
        guard rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else { return false }
        let screen = CGRect(origin: .zero, size: size)
        let visible = rect.intersection(screen)
        guard !visible.isNull, !visible.isEmpty else { return false }
        let fraction = (visible.width * visible.height) / (rect.width * rect.height)
        return fraction >= minimumVisibleFraction
    }

    /// The four rectangles that tile the screen around `hole`: above, below,
    /// left and right. Their union is the whole screen minus the hole's
    /// bounding box, and none of them overlaps it.
    ///
    /// The hole's ROUNDED CORNERS are left unblocked -- the four rects tile
    /// against its bounding box, so the little corner slivers outside the round
    /// but inside the box pass taps through. That is the right way round: a tap
    /// a couple of points outside a rounded target still reaches the target,
    /// rather than dying on the scrim.
    static func blockingRects(around hole: CGRect, in size: CGSize) -> [CGRect] {
        let screen = CGRect(origin: .zero, size: size)
        let clipped = hole.intersection(screen)
        // A hole entirely off screen blocks everything -- there is nothing to
        // pass through to.
        guard !clipped.isNull, !clipped.isEmpty else { return [screen] }
        return [
            CGRect(x: 0, y: 0, width: size.width, height: max(0, clipped.minY)),
            CGRect(x: 0, y: clipped.maxY, width: size.width, height: max(0, size.height - clipped.maxY)),
            CGRect(x: 0, y: clipped.minY, width: max(0, clipped.minX), height: clipped.height),
            CGRect(x: clipped.maxX, y: clipped.minY, width: max(0, size.width - clipped.maxX), height: clipped.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }
}
