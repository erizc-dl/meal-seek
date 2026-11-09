//
//  AccountView.swift
//  Meal Seek
//
//  Profile header, live servings stepper, and settings groups for editing
//  cuisines/allergies plus a regenerate-week action. There is no auth — the
//  display name is cosmetic and stored locally in preferences.
//

import SwiftUI
import UniformTypeIdentifiers

struct AccountView: View {
    let recipeStore: RecipeStore
    let preferencesStore: PreferencesStore
    let planStore: WeekPlanStore
    /// Read at generation time and by the recipe library's rating filter.
    let ratingsStore: RatingsStore
    /// Included so a data backup/restore can round-trip grocery bought-state.
    let groceryStateStore: GroceryStateStore
    /// Shared with Home and Grocery so "Regenerate week" acts on the week the
    /// user is actually looking at.
    let weekContext: WeekContext

    @Environment(\.walkthrough) private var walkthrough

    /// Account's push stack. Bound so completing the walkthrough -- which ends
    /// two levels deep, in a recipe's detail screen -- can hand the app back at
    /// Account's root instead of leaving the user somewhere the walkthrough
    /// navigated them to.
    @State private var navigationPath = NavigationPath()

    @State private var showRenameAlert = false
    @State private var nameDraft = ""
    @State private var showRegenerateAlert = false
    /// Presented here — not in the settings screens — because their deferred
    /// exit offer fires from onDisappear, after they have already popped.
    @State private var showPreferencesChangedPrompt = false
    @State private var showFeedbackSheet = false
    /// Composed feedback captured when the sheet's share button is tapped;
    /// promoted to `feedbackShare` only after the sheet finishes dismissing
    /// so the share sheet never stacks on top of it.
    @State private var pendingFeedbackText: String?
    @State private var feedbackShare: FeedbackShare?
    @State private var toastText: String?
    /// Set when a regenerate from this screen fails outright; presents the
    /// designed error screen as a sheet. A partial regenerate instead saves and
    /// shows a toast, so valid work is never hidden here.
    @State private var generationErrorItem: GenerationErrorItem?

    // Data backup / restore.
    /// The written temporary backup file, presented for sharing; cleared and
    /// deleted once the share sheet dismisses.
    @State private var backupExport: BackupExport?
    @State private var showRestorePicker = false
    /// A validated backup awaiting the user's explicit confirmation to apply.
    @State private var pendingRestore: BackupArchive?
    /// Restore validation/failure text, shown in an alert (nothing is changed).
    @State private var restoreErrorMessage: String?
    /// Restore completion summary, shown in an alert after a successful apply.
    @State private var restoreSummaryMessage: String?

    private static let feedbackAddress = "mealseek.app@protonmail.com"

    private var calendar: Calendar { Calendar.current }
    private var currentWeekStart: Date { calendar.mondayOfWeek(containing: Date()) }
    private var displayedWeekStart: Date { weekContext.displayedWeekStart }
    private var isPastWeek: Bool { displayedWeekStart < currentWeekStart }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    profileHeader
                    servingsCard
                    sectionHeader("PREFERENCES")
                    preferencesGroup
                    languageFootnote
                    sectionHeader("RECIPES")
                    recipesGroup
                    sectionHeader("PLAN")
                    planGroup
                    sectionHeader("DATA")
                    dataGroup
                    dataFootnote
                    sectionHeader("HELP")
                    helpGroup
                    sectionHeader("SUPPORT")
                    supportGroup
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .spotlightScreen()
            // Completing the walkthrough hands the app back at Account's root.
            // WITHOUT animation, so the tab switch to Home is the only
            // transition the user sees rather than a pop racing it.
            .onChange(of: walkthrough.completionCount) {
                navigationPath = NavigationPath()
            }
            .alert("Your kitchen's name", isPresented: $showRenameAlert) {
                TextField("Name", text: $nameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveName() }
            }
            .regenerateConfirmation(
                isPresented: $showRegenerateAlert,
                hasManualEdits: planStore.plan(for: displayedWeekStart)?.hasManualEdits == true
            ) {
                generateDisplayedWeek()
            }
            .alert("Your preferences changed. Regenerate this week to match?", isPresented: $showPreferencesChangedPrompt) {
                Button("Keep current", role: .cancel) {}
                Button("Regenerate") { generateDisplayedWeek() }
            }
            .sheet(isPresented: $showFeedbackSheet, onDismiss: presentPendingFeedbackShare) {
                FeedbackSheetView(address: Self.feedbackAddress) { composedText in
                    pendingFeedbackText = composedText
                }
            }
            .sheet(item: $feedbackShare) { share in
                ShareSheet(items: [FeedbackShareText(text: share.text)])
            }
            .sheet(item: $generationErrorItem, onDismiss: presentPendingFeedbackShare) { item in
                generationErrorSheet(item.error)
            }
            .sheet(item: $backupExport, onDismiss: cleanUpBackupExport) { export in
                // JSON file share (UTType.json) — the opposite of the feedback
                // share, which declares plain text. The temporary file is
                // deleted in onComplete / onDismiss.
                ShareSheet(
                    items: [BackupFileActivityItem(url: export.url)],
                    onComplete: cleanUpBackupExport
                )
            }
            .fileImporter(
                isPresented: $showRestorePicker,
                allowedContentTypes: [.json]
            ) { result in
                handleRestorePick(result)
            }
            .alert(
                "Replace all data?",
                isPresented: presenting($pendingRestore),
                presenting: pendingRestore
            ) { archive in
                Button("Cancel", role: .cancel) {}
                Button("Replace", role: .destructive) { applyRestore(archive) }
            } message: { archive in
                Text(restoreConfirmationMessage(for: archive))
            }
            .alert(
                "Couldn't restore",
                isPresented: presenting($restoreErrorMessage),
                presenting: restoreErrorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                "Backup restored",
                isPresented: presenting($restoreSummaryMessage),
                presenting: restoreSummaryMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .toast($toastText)
        }
    }

    /// A Bool binding derived from an optional-state var, for `.alert`/`.sheet`
    /// presenters: reads as "is set", and clears the source when dismissed.
    private func presenting<T>(_ source: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }

    // MARK: Profile header

    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.brandOrangePale)
                Image(systemName: SFSymbols.chefHat)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.brandOrange)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    nameDraft = preferencesStore.preferences.displayName
                    showRenameAlert = true
                } label: {
                    Text(preferencesStore.preferences.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                }
                .buttonStyle(PressableButtonStyle())

                Text(mealsPlannedSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    /// Live count of meals in the CURRENT week's plan (empty slots lower it).
    private var mealsPlannedSubtitle: String {
        guard let plan = planStore.plan(for: currentWeekStart) else {
            return String(localized: "No plan for this week yet")
        }
        return String(localized: "\(plan.meals.count) meals planned this week")
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        preferencesStore.preferences.displayName = trimmed
        preferencesStore.save()
    }

    // MARK: Servings

    /// The one and only servings control. Saves immediately on change; grocery
    /// quantities rescale on their own because the builder reads householdSize.
    /// Nothing else happens — no prompt, no regeneration, no unchecking.
    private var servingsCard: some View {
        ServingsStepper(value: servingsBinding, label: "Cooking for")
    }

    private var servingsBinding: Binding<Int> {
        Binding(
            get: { preferencesStore.preferences.householdSize },
            set: { newValue in
                guard newValue != preferencesStore.preferences.householdSize else { return }
                preferencesStore.preferences.householdSize = newValue
                preferencesStore.save()
            }
        )
    }

    // MARK: Settings groups

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.textTertiary)
            .padding(.top, 6)
            .padding(.leading, 2)
    }

    private var preferencesGroup: some View {
        VStack(spacing: 0) {
            NavigationLink {
                CuisinesSettingsView(
                    preferencesStore: preferencesStore,
                    planStore: planStore,
                    weekContext: weekContext,
                    catalog: recipeStore.catalog,
                    onExitWithChanges: { showPreferencesChangedPrompt = true }
                )
            } label: {
                settingsRow(
                    icon: "globe",
                    title: "Cuisines",
                    detail: preferencesStore.preferences.cuisines.count.formatted()
                )
            }
            .buttonStyle(PressableButtonStyle())

            groupDivider

            NavigationLink {
                AllergiesSettingsView(
                    recipeStore: recipeStore,
                    preferencesStore: preferencesStore,
                    planStore: planStore,
                    weekContext: weekContext,
                    onExitWithChanges: { showPreferencesChangedPrompt = true }
                )
            } label: {
                settingsRow(
                    icon: "exclamationmark.circle",
                    title: "Allergies",
                    detail: preferencesStore.preferences.allergens.count.formatted()
                )
            }
            .buttonStyle(PressableButtonStyle())

            groupDivider

            // Opens Meal Seek's own page in iOS Settings, where iOS shows the
            // per-app Language option (present because the app ships multiple
            // localizations). We deliberately don't build an in-app switcher.
            Button {
                openAppSettings()
            } label: {
                settingsRow(icon: "character.bubble", title: "Language", detail: nil)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .background(Color.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    /// One-sentence clarification that the Language row scopes to Meal Seek, not
    /// the whole device. Same footnote treatment as the DATA disclaimer.
    private var languageFootnote: some View {
        Text("Language sets the display language for Meal Seek only, not your whole phone.")
            .font(.system(size: 11))
            .foregroundStyle(.textTertiary)
            .padding(.horizontal, 2)
    }

    private var recipesGroup: some View {
        VStack(spacing: 0) {
            NavigationLink {
                RecipeLibraryView(recipeStore: recipeStore, ratingsStore: ratingsStore,
                                  planStore: planStore)
            } label: {
                settingsRow(
                    icon: "book.closed",
                    title: "Recipe library",
                    detail: recipeStore.recipes.count.formatted()
                )
            }
            .buttonStyle(PressableButtonStyle())
            // Points at the ROW, not the group. The group holds two
            // destinations and only one is right; spotlighting both is what let
            // a device tester open Pantry staples "correctly". The cutout
            // overhangs the group's rounded top corners slightly -- accepted.
            .spotlightTarget(.recipeLibrary, cornerRadius: 12)

            Rectangle()
                .fill(Color.backgroundSecondary)
                .frame(height: 1)
                .padding(.leading, 14)

            NavigationLink {
                PantrySettingsView(preferencesStore: preferencesStore, recipeStore: recipeStore)
            } label: {
                settingsRow(
                    icon: "cabinet",
                    title: "Pantry staples",
                    detail: pantryDetail
                )
            }
            .buttonStyle(PressableButtonStyle())
        }
        .background(Color.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    /// "Default" until the user has actually changed something, then how many
    /// — so the row itself says whether they have a customization to find.
    private var pantryDetail: String {
        let changed = ShoppingListBuilder.userChangedNames(preferencesStore.preferences.pantryOverrides).count
        return changed == 0 ? String(localized: "Default") : String(localized: "\(changed) changed")
    }

    private var planGroup: some View {
        Button {
            showRegenerateAlert = true
        } label: {
            settingsRow(
                icon: "arrow.clockwise",
                title: "Regenerate week",
                detail: nil,
                showsChevron: false,
                disabled: isPastWeek
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isPastWeek) // past weeks are read-only
        .background(Color.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    // MARK: Data (backup / restore)

    private var dataGroup: some View {
        VStack(spacing: 0) {
            Button {
                backUpData()
            } label: {
                settingsRow(icon: "arrow.up.doc", title: "Back up data", detail: nil, showsChevron: false)
            }
            .buttonStyle(PressableButtonStyle())

            groupDivider

            Button {
                showRestorePicker = true
            } label: {
                settingsRow(icon: "arrow.down.doc", title: "Restore from backup", detail: nil, showsChevron: false)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .background(Color.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    /// The file leaves the device (Files, AirDrop, iCloud), so name what it
    /// carries — including the kitchen's display name (addition #2).
    private var dataFootnote: some View {
        Text("Backups include your kitchen name and all your saved data. Anyone you share the file with can read it.")
            .font(.system(size: 11))
            .foregroundStyle(.textTertiary)
            .padding(.horizontal, 2)
    }

    private func settingsRow(
        icon: String,
        title: LocalizedStringKey,
        detail: String?,
        showsChevron: Bool = true,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(disabled ? .textTertiary : .brandOrange)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(disabled ? Color.backgroundSecondary : .brandOrangePale))

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(disabled ? .textTertiary : .textPrimary)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.textTertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var groupDivider: some View {
        Divider().padding(.leading, 56)
    }

    // MARK: Help

    /// The permanent way back into "Plan your first week". Once the Home
    /// invitation is dismissed this is the only route, so it always replays from
    /// the start rather than resuming -- someone who chose to watch it again
    /// does not want to be dropped into step 6.
    private var helpGroup: some View {
        Button {
            walkthrough.start()
        } label: {
            settingsRow(
                icon: "sparkles",
                title: "Plan your first week",
                detail: nil,
                showsChevron: false
            )
        }
        .buttonStyle(PressableButtonStyle())
        .background(Color.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    // MARK: Feedback

    private var supportGroup: some View {
        Button {
            sendFeedback()
        } label: {
            settingsRow(
                icon: "envelope",
                title: "Send feedback",
                detail: nil,
                showsChevron: false
            )
        }
        .buttonStyle(PressableButtonStyle())
        .background(Color.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    private func sendFeedback() {
        showFeedbackSheet = true
    }

    /// Deep-links to Meal Seek's own page in iOS Settings, where the per-app
    /// Language option lives. We never read or write AppleLanguages ourselves.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Runs on the feedback sheet's onDismiss: if the tester tapped "Share
    /// feedback" (rather than swiping the sheet away), present the share
    /// sheet now that the first sheet is fully gone.
    private func presentPendingFeedbackShare() {
        guard let text = pendingFeedbackText else { return }
        pendingFeedbackText = nil
        feedbackShare = FeedbackShare(text: text)
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) { toastText = text }
    }

    // MARK: Backup / restore actions

    private func makeBackupService() -> BackupService {
        BackupService(
            preferencesStore: preferencesStore,
            ratingsStore: ratingsStore,
            planStore: planStore,
            groceryStateStore: groceryStateStore,
            weekContext: weekContext,
            userRecipeStore: recipeStore.userRecipes,
            recipes: recipeStore.recipes,
            recipeSchemaVersion: recipeStore.schemaVersion
        )
    }

    /// Writes the backup to a temp file and presents the system share sheet.
    /// On failure, shows the existing toast — never an empty share sheet.
    private func backUpData() {
        do {
            let url = try makeBackupService().writeTemporaryBackup()
            backupExport = BackupExport(url: url)
        } catch {
            showToast(String(localized: "Couldn't create the backup file"))
        }
    }

    /// Deletes the temporary backup file once the share sheet is gone. Safe to
    /// run twice (onComplete then onDismiss) — a missing file is ignored.
    private func cleanUpBackupExport() {
        guard let export = backupExport else { return }
        try? FileManager.default.removeItem(at: export.url)
        backupExport = nil
    }

    /// Reads and validates the picked file. On success, stages it for the
    /// confirmation dialog; on failure, shows a clear message and changes nothing.
    private func handleRestorePick(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                switch makeBackupService().validate(data) {
                case .success(let archive):
                    pendingRestore = archive
                case .failure(let error):
                    restoreErrorMessage = error.errorDescription
                }
            } catch {
                restoreErrorMessage = String(localized: "This file couldn't be read. Nothing was changed.")
            }
        case .failure:
            restoreErrorMessage = String(localized: "Couldn't open that file. Nothing was changed.")
        }
    }

    /// Applies a confirmed restore, then reports the outcome. The stores update
    /// their own in-memory state, so every tab reflects the restore at once.
    private func applyRestore(_ archive: BackupArchive) {
        switch makeBackupService().restore(archive) {
        case .success(let summary):
            // UserRecipeStore updates itself, but the merged pool RecipeStore
            // hands to every view is rebuilt only on request.
            recipeStore.reloadUserRecipes()
            restoreSummaryMessage = restoreCompletionMessage(for: summary)
        case .failure(let error):
            restoreErrorMessage = error.errorDescription
        }
    }

    /// Names what will be replaced and when the backup was made, and flags the
    /// display name so the user knows their kitchen name is in the file.
    private func restoreConfirmationMessage(for archive: BackupArchive) -> String {
        String(localized: "This replaces your current preferences (including your kitchen name), ratings, meal plans, grocery list, and your own recipes with the backup from \(Self.dateText(archive.createdAt)). This can't be undone.")
    }

    private func restoreCompletionMessage(for summary: BackupService.RestoreSummary) -> String {
        var lines = [String(localized: "Your data was restored from the backup made \(Self.dateText(summary.backupDate)).")]
        if summary.droppedRatingCount > 0 {
            lines.append(String(localized: "\(summary.droppedRatingCount) ratings for recipes no longer in the library were dropped."))
        }
        if summary.droppedMealCount > 0 {
            lines.append(String(localized: "\(summary.droppedMealCount) planned meals referencing missing recipes were dropped."))
        }
        // Above the regeneration line on purpose: this is the only safety
        // message in the set, and a user who reads one line should read this one.
        if summary.removedUnsafeCount > 0 {
            lines.append(String(localized: "\(summary.removedUnsafeCount) planned dishes were removed because they contain allergens you avoid."))
        }
        if summary.regeneratedWeekCount > 0 {
            lines.append(String(localized: "\(summary.regeneratedWeekCount) weeks were regenerated to replace missing recipes."))
        }
        if summary.recipeSchemaMismatch {
            lines.append(String(localized: "This backup was made against a different recipe set."))
        }
        return lines.joined(separator: "\n\n")
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Actions

    /// Same behavior as the refresh button on Home: regenerate the displayed
    /// week and persist. Only reachable for the current or a future week.
    ///
    /// Regenerate replaces the plan wholesale and must never emit
    /// FeedbackEvents — a reshuffle is not a dislike signal. Do not
    /// reimplement this as a loop of removeMeal calls.
    private func generateDisplayedWeek() {
        let outcome = PlanGenerator.generate(
            recipes: recipeStore.recipes,
            preferences: preferencesStore.preferences,
            ratings: ratingsStore.ratings,
            weekStartDate: displayedWeekStart,
            databaseLoadFailureReason: recipeStore.loadFailureReason
        )
        switch outcome {
        case .success(let success):
            withAnimation(.easeInOut(duration: 0.25)) {
                planStore.save(success.plan)
            }
            if success.warning != nil {
                showToast(String(localized: "Some meals couldn't be planned for your current settings"))
            }
        case .failure(let error):
            generationErrorItem = GenerationErrorItem(error: error)
        }
    }

    // MARK: Generation error sheet

    /// The designed error screen, presented on `backgroundPrimary`. The
    /// preferences the user needs are on this same tab, so "Adjust Preferences"
    /// just dismisses; "Try Again" dismisses and regenerates. "Report this
    /// problem" stages the diagnostic and lets the sheet's `onDismiss` present
    /// the share sheet, exactly like the feedback flow, so sheets never stack.
    private func generationErrorSheet(_ error: WeekGenerationError) -> some View {
        GenerationErrorView(
            error: error,
            onPrimaryAction: {
                let action = error.primaryAction
                generationErrorItem = nil
                if action == .tryAgain {
                    generateDisplayedWeek()
                }
            },
            onReport: {
                let report = DiagnosticReport.forGenerationFailure(
                    error: error,
                    recipes: recipeStore.recipes,
                    preferences: preferencesStore.preferences
                )
                pendingFeedbackText = report.text
                generationErrorItem = nil
            }
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }
}

/// Wraps a generation error for `.sheet(item:)` presentation from Account.
struct GenerationErrorItem: Identifiable {
    let id = UUID()
    let error: WeekGenerationError
}

/// Wraps the written backup file's URL for `.sheet(item:)` presentation.
struct BackupExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// Shares the backup as a JSON *file*, so destinations save it to Files /
/// iCloud Drive / AirDrop rather than pasting its text inline. This is the
/// opposite of FeedbackShareText, which declares plain text on purpose.
final class BackupFileActivityItem: NSObject, UIActivityItemSource {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    /// Declares the payload as JSON so targets treat it as a file (req 11).
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.json.identifier
    }

    /// The suggested name for the shared file (e.g. as a mail attachment).
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        url.lastPathComponent
    }
}
