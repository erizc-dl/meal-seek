//
//  StaggeredEntrance.swift
//  Meal Seek
//
//  Entrance-animation timing and the one-shot reveal modifier used when a
//  generated week resolves. Values honor the design system's easeInOut-only
//  rule (no springs): the day cards cascade in with a staggered offset+opacity
//  reveal, the warning banner follows them, and the error view fades+scales.
//  Reduce Motion collapses all movement to a plain opacity fade with no stagger.
//

import SwiftUI

/// Central timing so the cascade lives in one place and can't drift.
enum EntranceTiming {
    /// Per-card entrance duration (easeInOut, not a spring — see DESIGN_SYSTEM §6).
    static let cardDuration = 0.35
    /// Cards start this far below their final position.
    static let cardOffset: CGFloat = 12
    /// The banner starts this far above (negative = slides down into place).
    static let bannerOffset: CGFloat = -12
    /// Default gap between consecutive cards, top to bottom.
    static let perCardDelay = 0.040
    /// Cap on the stagger span (first card start → last card start) so the
    /// cascade never feels slow regardless of card count.
    static let maxStaggerSpan = 0.400
    /// Error view fade+scale duration.
    static let errorDuration = 0.20
    /// Error view starting scale.
    static let errorScale: CGFloat = 0.96
    /// Reduce Motion fade duration (replaces every movement).
    static let reduceMotionFade = 0.15

    /// Delay for the card at `index` of `count`. The per-card gap is compressed
    /// proportionally when the default 40 ms spacing would push the last card
    /// past `maxStaggerSpan`, rather than truncating the cascade.
    static func cardDelay(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let gap = min(perCardDelay, maxStaggerSpan / Double(count - 1))
        return Double(index) * gap
    }

    /// When the banner reveals: after the last card has finished animating.
    static func bannerDelay(cardCount: Int) -> Double {
        cardDelay(index: max(0, cardCount - 1), count: cardCount) + cardDuration
    }
}

/// A one-shot entrance reveal: fades — and, unless Reduce Motion is on, slides —
/// a view into place on appear. It re-fires whenever the host changes the
/// subtree's identity (e.g. a new generation token), which is how regenerating
/// a week replays the cascade instead of cross-fading in place.
struct EntranceReveal: ViewModifier {
    let delay: Double
    let offsetY: CGFloat
    let reduceMotion: Bool

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: (shown || reduceMotion) ? 0 : offsetY)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeInOut(duration: EntranceTiming.reduceMotionFade)
                    : .easeInOut(duration: EntranceTiming.cardDuration).delay(delay)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    /// Reveals the view on appear with the entrance timing. Under Reduce Motion
    /// the `delay` and `offsetY` are ignored in favor of a plain fade.
    func entranceReveal(delay: Double, offsetY: CGFloat, reduceMotion: Bool) -> some View {
        modifier(EntranceReveal(delay: delay, offsetY: offsetY, reduceMotion: reduceMotion))
    }
}
