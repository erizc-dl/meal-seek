//
//  Toast.swift
//  Meal Seek
//
//  The bottom-capsule toast (design system §8 "Copied toast"), extracted from
//  AccountView so sheets can show it too. Attach `.toast($text)` to a screen
//  and show by setting the binding inside withAnimation(.easeInOut(0.25));
//  the modifier hides it again 2 seconds later.
//

import SwiftUI

extension View {
    func toast(_ text: Binding<String?>) -> some View {
        modifier(ToastModifier(text: text))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let text {
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.textOnPale)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.brandOrangePale))
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .onChange(of: text) { _, newValue in
                guard newValue != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeInOut(duration: 0.25)) { text = nil }
                }
            }
    }
}
