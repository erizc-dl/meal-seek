//
//  FeedbackSheetView.swift
//  Meal Seek
//
//  Beta-feedback composer presented as a sheet from Account. The tester
//  writes a message and hands it to the system share sheet, so feedback
//  travels through whatever app they actually use — no dependency on Apple
//  Mail (whose MFMailComposeViewController fails silently for anyone else).
//  The destination address is shown and copyable as an always-available
//  fallback. Drafts are deliberately not persisted: dismissing discards.
//

import SwiftUI
import UniformTypeIdentifiers

struct FeedbackSheetView: View {
    let address: String
    /// Receives the fully composed share text. The sheet dismisses itself
    /// right after; the caller presents the share sheet once the dismissal
    /// completes so the tester never sits behind two stacked sheets.
    let onShare: (String) -> Void

    @State private var message = ""
    @State private var toastText: String?
    @Environment(\.dismiss) private var dismiss

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The toast is anchored to this upper section, not the whole
            // sheet, so it never lands on the share button or address row.
            VStack(alignment: .leading, spacing: 14) {
                Text("Send feedback")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)

                Text("Write your message, then pick any app to send it to the developer.")
                    .font(.system(size: 13))
                    .foregroundStyle(.textSecondary)

                editor
            }
            .toast($toastText)

            addressRow

            PrimaryButton(title: String(localized: "Share feedback"), isEnabled: !trimmedMessage.isEmpty) {
                onShare(composedText)
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: Message editor

    /// White input surface like the search fields (radius 12, no shadow).
    /// TextEditor has no placeholder, so one is overlaid while empty.
    private var editor: some View {
        TextEditor(text: $message)
            .font(.system(size: 14))
            .foregroundStyle(.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 120, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundCard))
            .overlay(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What's working? What isn't?")
                        .font(.system(size: 14))
                        .foregroundStyle(.textTertiary)
                        .padding(.leading, 13)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: Address fallback

    private var addressRow: some View {
        HStack(spacing: 12) {
            Text(address)
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Button {
                copyAddress()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.brandOrange)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.brandOrangePale))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundCard))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        withAnimation(.easeInOut(duration: 0.25)) { toastText = "Feedback address copied" }
    }

    // MARK: Share text

    /// The tester's words plus device context only — never recipe,
    /// preference, rating, or plan data. The address is in the body because
    /// targets like Messages have no recipient field.
    private var composedText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return """
        \(trimmedMessage)

        \(address)
        App version: \(version)
        Build: \(build)
        iOS: \(UIDevice.current.systemVersion)
        """
    }
}

/// Wraps composed feedback for `.sheet(item:)` presentation after the
/// feedback sheet has dismissed.
struct FeedbackShare: Identifiable {
    let id = UUID()
    let text: String
}

/// Hands the plain text to every target and adds a subject for the ones that
/// support one (mail-type destinations).
final class FeedbackShareText: NSObject, UIActivityItemSource {
    static let subject = "Meal Seek beta feedback"

    private let text: String

    init(text: String) {
        self.text = text
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text
    }

    /// Declares the payload as plain text. Without this, mail-type targets
    /// treat the item as a file and attach it as feedback.txt instead of
    /// composing an inline message.
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.plainText.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        Self.subject
    }
}
