//
//  Theme.swift
//  Meal Seek
//
//  Canonical design-system colors, a hex Color initializer, and small shared
//  helpers used across views. See the ui-design skill for the source of truth.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17, 255)
        case 6: // RRGGBB
            (r, g, b, a) = (value >> 16, value >> 8 & 0xFF, value & 0xFF, 255)
        case 8: // AARRGGBB
            (r, g, b, a) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF, value >> 24)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// Declared on `ShapeStyle where Self == Color` so both the implicit-member
// shorthand (`.foregroundStyle(.textPrimary)`) and the explicit form
// (`Color.textPrimary`) resolve — the same pattern SwiftUI uses for `.red`.
extension ShapeStyle where Self == Color {
    // MARK: Brand orange — the one accent, in three layers
    static var brandOrange: Color { Color(hex: "#FF6B35") }
    static var brandOrangeMid: Color { Color(hex: "#FF8C5A") }
    static var brandOrangePale: Color { Color(hex: "#FFF0E8") }

    // MARK: Warm neutrals
    static var backgroundPrimary: Color { Color(hex: "#FAFAF8") }
    static var backgroundSecondary: Color { Color(hex: "#F4F3EF") }
    static var backgroundCard: Color { Color(hex: "#FFFFFF") }

    // MARK: Text
    static var textPrimary: Color { Color(hex: "#1A1A1A") }
    static var textSecondary: Color { Color(hex: "#6B6B6B") }
    static var textTertiary: Color { Color(hex: "#ABABAB") }
    static var textOnPale: Color { Color(hex: "#993C1D") }

    // Chip text on the muted #F4F3EF surface (per the onboarding spec).
    static var chipTextUnselected: Color { Color(hex: "#5F5E5A") }

    // MARK: Walkthrough scrim
    /// The dim behind "Plan your first week" -- the app's ONLY visible use of
    /// black. Everywhere else `.black` appears solely inside a shadow color.
    ///
    /// The 0.05 shadow ceiling (DESIGN_SYSTEM §5) governs SHADOWS and does not
    /// apply here: a scrim is a surface, not a shadow. Over `#FAFAF8` this
    /// composites to roughly `#706F70`, which keeps a white coach card at high
    /// contrast while still reading as "the app is paused, not off".
    static var walkthroughScrim: Color { Color.black.opacity(0.55) }
}

/// Button press feedback per the design system: scale 0.97, opacity 0.85.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

enum SFSymbols {
    /// Resolves to the first chef-hat-like SF Symbol that actually exists on this
    /// OS, so the icon never renders blank regardless of SF Symbols version.
    static let chefHat: String = {
        // No true chef-hat/toque symbol exists in SF Symbols, so fall back to the
        // most recognizable cooking glyph that does. See the ui-design skill's
        // "chef-hat-like symbol" note.
        for candidate in ["chef.hat", "toque", "frying.pan.fill", "cooktop", "fork.knife"] {
            if UIImage(systemName: candidate) != nil { return candidate }
        }
        return "fork.knife"
    }()
}

/// A simple wrapping layout for capsule chips (left-to-right, top-to-bottom).
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widestRow = max(widestRow, x - spacing)
        }
        return CGSize(width: min(widestRow, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
