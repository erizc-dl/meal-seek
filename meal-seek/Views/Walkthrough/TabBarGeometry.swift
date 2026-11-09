//
//  TabBarGeometry.swift
//  Meal Seek
//
//  Where the tab items are, for the walkthrough steps that point at one.
//
//  This exists because `.tabItem` labels never enter the SwiftUI layout tree --
//  they are configuration, rendered by UIKit -- so a tab item cannot publish a
//  `spotlightTarget` anchor the way every other target does. The rect has to be
//  derived instead.
//
//  THESE ARE MEASURED CONSTANTS, NOT DERIVED ONES, and that is the weak point.
//  iOS 26 does not draw the classic full-width bar: it draws a CENTERED FLOATING
//  PILL inset from both screen edges, so "divide the screen width by the number
//  of tabs" -- the obvious derivation, and the one this was planned as -- puts
//  the outer items in the wrong place entirely. The values below were read off a
//  screenshot on iPhone 17 Pro / iOS 26 (402x874pt):
//
//      pill spans x 66.6...336.6pt (270 wide), y 792.3...852.7pt (60 tall)
//      item centers measured at 115 / 201.7 / 287.3pt
//      this derivation gives  111.6 / 201.6 / 291.6pt
//
//  Under 4pt of error on the outer items and under 1pt in the middle, which a
//  cutout with 6pt of padding absorbs. But the inset is assumed to scale with
//  screen width, and that is UNVERIFIED on any other device.
//
//  SO THE DERIVATION IS ALLOWED TO FAIL. `rect(for:of:in:)` returns nil rather
//  than a rect it does not believe: if the result falls outside the screen, is
//  narrower than `minimumItemWidth` (40pt -- below the 44pt HIG target, so
//  nothing real is that small), or sits above the bottom safe-area inset, the
//  calibration did not survive whatever device this is.
//
//  A nil means the step draws NO CUTOUT: full scrim, coach card only. That is
//  the important half of the design. A silently wrong cutout points at empty
//  chrome and looks broken; no cutout looks like a choice, and the card still
//  names the destination -- and the tab bar is the one piece of chrome a user
//  can already find without being shown.
//

import SwiftUI

enum TabBarGeometry {
    /// Height of the floating pill.
    static let height: CGFloat = 60
    /// Gap between the pill's bottom edge and the bottom of the screen.
    static let bottomMargin: CGFloat = 21
    /// Inset from each screen edge to the pill, at the calibration width.
    static let horizontalInset: CGFloat = 66
    /// The screen width those constants were measured at.
    static let calibrationWidth: CGFloat = 402
    /// Below this, the derived item is too narrow to be a real tab item -- the
    /// HIG minimum target is 44pt, so nothing legitimate lands under 40.
    static let minimumItemWidth: CGFloat = 40

    /// The on-screen rect of tab `index` of `count`, or nil when the derivation
    /// cannot be trusted on this device.
    ///
    /// `size` must be the FULL screen, safe areas included -- the overlay's
    /// GeometryReader already ignores them. `bottomInset` is the bottom safe-area
    /// inset, used to sanity-check that the pill sits where a tab bar can.
    static func rect(
        for index: Int,
        of count: Int,
        in size: CGSize,
        bottomInset: CGFloat
    ) -> CGRect? {
        guard count > 0, index >= 0, index < count, size.width > 0, size.height > 0 else { return nil }

        let inset = horizontalInset * (size.width / calibrationWidth)
        let barWidth = size.width - inset * 2
        guard barWidth > 0 else { return nil }

        let itemWidth = barWidth / CGFloat(count)
        let rect = CGRect(
            x: inset + itemWidth * CGFloat(index),
            y: size.height - bottomMargin - height,
            width: itemWidth,
            height: height
        )

        // Too narrow to be a tab item on any real device.
        guard rect.width >= minimumItemWidth else { return nil }
        // Off-screen in any direction.
        let screen = CGRect(origin: .zero, size: size)
        guard screen.contains(rect) else { return nil }
        // A tab bar lives in the bottom inset region. If the derived rect sits
        // entirely ABOVE it, the constants do not describe this device's bar.
        guard bottomInset <= 0 || rect.maxY > size.height - bottomInset else { return nil }

        return rect
    }
}
