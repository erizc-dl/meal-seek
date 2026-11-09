//
//  RegionCuisinePicker.swift
//  Meal Seek
//
//  The shared region/cuisine selection list used by onboarding and the
//  Cuisines settings screen (RegionRow's successor). Region cards collapse to
//  a cuisine/recipe count and expand — via the independent chevron — to
//  individually selectable cuisines. Selection is per-cuisine; a region's
//  checkbox reflects none / some / all of its cuisines. The picker never lets
//  a non-empty selection become empty: the tap that would is simply ignored.
//

import SwiftUI

struct RegionCuisinePicker: View {
    let catalog: CuisineCatalog
    /// Selected cuisine names, shared with the caller's preferences.
    @Binding var selection: Set<String>

    /// Local UI state — which cards are expanded. Collapsed by default,
    /// independent of selection.
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 12) {
            ForEach(catalog.regions) { region in
                regionCard(region)
            }
        }
    }

    // MARK: Region state

    private enum RegionState {
        case none, partial, full
    }

    private func state(of region: CuisineCatalog.Region) -> RegionState {
        let selectedCount = region.cuisines.count { selection.contains($0.name) }
        if selectedCount == 0 { return .none }
        return selectedCount == region.cuisines.count ? .full : .partial
    }

    private func checkboxSymbol(for state: RegionState) -> String {
        switch state {
        case .none: return "square"
        case .partial: return "minus.square"
        case .full: return "checkmark"
        }
    }

    // MARK: Card

    private func regionCard(_ region: CuisineCatalog.Region) -> some View {
        let state = state(of: region)
        let isExpanded = expanded.contains(region.name)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Selection tap target: everything except the chevron.
                Button {
                    toggleRegion(region)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: checkboxSymbol(for: state))
                            .font(.system(size: 17, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedNames.region(region.name))
                                .font(.system(size: 17, weight: .semibold))
                            Text(countLine(for: region))
                                .font(.system(size: 13))
                                .opacity(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())

                // Chevron tap target: independent expand/collapse.
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if isExpanded {
                            expanded.remove(region.name)
                        } else {
                            expanded.insert(region.name)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(region.cuisines) { cuisine in
                        cuisineRow(cuisine)
                    }
                }
                .padding(.leading, 29) // align under the name, past the checkbox
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(state == .full ? Color.white : .textOnPale)
        .padding(12)
        .background(state == .full ? Color.brandOrange : .brandOrangePale)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            // The partial state: pale like unselected, but ringed in orange
            // with a minus checkbox — distinct from both ends.
            if state == .partial {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.brandOrange, lineWidth: 1.5)
            }
        }
    }

    private func countLine(for region: CuisineCatalog.Region) -> String {
        let cuisines = String(localized: "\(region.cuisines.count) cuisines")
        let recipes = String(localized: "\(region.recipeCount) recipes")
        return "\(cuisines) · \(recipes)"
    }

    // MARK: Cuisine row

    private func cuisineRow(_ cuisine: CuisineCatalog.Cuisine) -> some View {
        Button {
            toggleCuisine(cuisine.name)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.contains(cuisine.name) ? "checkmark" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, alignment: .leading)
                Text(LocalizedNames.cuisine(cuisine.name))
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 8)
                Text("\(cuisine.recipeCount) recipes")
                    .font(.system(size: 12))
                    .opacity(0.8)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: Selection

    /// Region tap: select all its cuisines, or — when already full — deselect
    /// them all, refused if that would empty the overall selection.
    private func toggleRegion(_ region: CuisineCatalog.Region) {
        let names = Set(region.cuisines.map(\.name))
        var newSelection = selection
        if state(of: region) == .full {
            guard !selection.subtracting(names).isEmpty else { return }
            newSelection.subtract(names)
        } else {
            newSelection.formUnion(names)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            selection = newSelection
        }
    }

    /// Cuisine tap: toggle it, refusing to deselect the last selected cuisine
    /// overall. Deselecting a region's final cuisine deselects the region
    /// (its state derives from the cuisine set).
    private func toggleCuisine(_ name: String) {
        var newSelection = selection
        if newSelection.contains(name) {
            guard selection.count > 1 else { return }
            newSelection.remove(name)
        } else {
            newSelection.insert(name)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            selection = newSelection
        }
    }
}
