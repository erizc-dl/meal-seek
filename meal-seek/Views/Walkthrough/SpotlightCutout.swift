//
//  SpotlightCutout.swift
//  Meal Seek
//
//  The scrim-with-a-hole shape.
//
//  The scrim is drawn as ONE even-odd shape (which renders correctly) but its
//  hit blocking is built from FOUR PLAIN RECTANGLES around the hole. Those are
//  two different jobs and they must not share a mechanism, because
//  `SwiftUI.Path.contains(_:eoFill:)` -- the predicate `contentShape(_:eoFill:)`
//  hit-tests through -- MISHANDLES EVEN-ODD FOR CURVED SUBPATHS:
//
//      rect + rect          -> contains(eoFill: true) == false   (correct)
//      rect + roundedRect   -> contains(eoFill: true) == true    (WRONG)
//      rect + ellipse       -> contains(eoFill: true) == true    (WRONG)
//      CGPath .evenOdd      -> false                             (correct)
//
//  CoreGraphics' even-odd FILL is fine, so the hole always LOOKED right; only
//  taps were swallowed. Every cutout in this feature is a rounded rect, so
//  every one of them drew a hole the user could see and could not tap through.
//
//  Hence: the shape below is for RENDERING ONLY and is never hit-tested. The
//  blocking rects are plain `Rectangle`s that simply do not exist over the hole,
//  which needs no containment predicate at all and cannot regress if Apple
//  changes one.
//

import SwiftUI

struct SpotlightCutout: Shape {
    /// The hole, in the shape's own coordinate space.
    var hole: CGRect
    /// Corner radius of the hole.
    var radius: CGFloat

    /// Animates the hole between steps so the spotlight travels rather than
    /// cutting. Without this the Shape would redraw discontinuously and
    /// `.animation` on the parent would have nothing to interpolate.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(hole.origin.x, hole.origin.y),
                AnimatablePair(hole.size.width, hole.size.height)
            )
        }
        set {
            hole = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        // Clamped so a degenerate hole (a target mid-transition, or one that
        // has not been laid out yet) cannot produce an invalid corner radius.
        let r = min(radius, min(hole.width, hole.height) / 2)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: r, height: r))
        return path
    }
}
