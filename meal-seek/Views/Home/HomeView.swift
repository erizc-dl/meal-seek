//
//  HomeView.swift
//  Meal Seek
//
//  The week plan screen: day-by-day arrow navigation across weeks, a Monday-
//  first week strip, and the selected day's three meal cards. Past weeks are
//  read-only; future weeks (up to 4 ahead) are planned on demand.
//

import SwiftUI

struct HomeView: View {
    let recipeStore: RecipeStore
    let preferencesStore: PreferencesStore
    let planStore: WeekPlanStore
    /// Read-only here: drives the grocery nudge card's unbought count.
    let groceryStateStore: GroceryStateStore
    /// Read at generation time only — rating a recipe never mutates the
    /// currently displayed week.
    let ratingsStore: RatingsStore
    /// Shared with the Grocery tab so it lists the same week being viewed here.
    let weekContext: WeekContext
    /// The root tab selection, so the grocery nudge card can switch tabs.
    @Binding var selectedTab: RootView.Tab

    /// "Plan your first week", read for the invitation card and reported to
    /// when the user does something a step is waiting on.
    @Environment(\.walkthrough) private var walkthrough
    @State private var walkthroughToast: String?
    /// The last completion this screen has already celebrated, so one
    /// completion produces exactly one toast however many times the view
    /// appears or updates.
    @State private var celebratedCompletionCount = 0

    @State private var showRegenerateAlert = false
    /// Non-nil while the meal picker sheet is up, identifying the slot it fills.
    @State private var pickerTarget: MealSlotTarget?
    /// Non-nil while the dish selection sheet is up, identifying its slot.
    @State private var dishSelectionTarget: MealSlotTarget?
    /// Non-nil while the share sheet is up, holding the rendered week card.
    @State private var shareItem: ShareCardImage?
    @State private var showShareFailedToast = false
    /// The generation lifecycle for the displayed week. `.failed`/`.generating`
    /// are explicit overrides; `.idle`/`.loaded` render from whether a plan
    /// exists. Replaces the old separate error/loaded flags.
    @State private var generationState: GenerationState = .idle
    /// Set when the displayed week generated only partially; drives the
    /// non-blocking warning banner above the meals.
    @State private var generationWarning: WeekGenerationWarning?
    /// Bumped on every completed generation so the day-card subtree re-inits and
    /// the entrance cascade replays (rather than cross-fading in place).
    @State private var generationToken = 0
    /// Non-nil while the diagnostic share sheet is up.
    @State private var diagnosticShare: FeedbackShare?
    /// When on, all entrance movement is replaced by a plain opacity fade.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The active-language store, threaded into the off-environment share-card
    /// renderer (ImageRenderer builds that view outside this environment).
    @Environment(\.recipeTranslations) private var translations

    /// One editable slot: a meal type on the selected day, and optionally the
    /// one dish within it being replaced.
    ///
    /// `dishID == nil` means "fill this empty slot" — the whole-slot write.
    /// A non-nil `dishID` means "swap exactly this dish", which is the path that
    /// must never disturb the slot's other dishes.
    struct MealSlotTarget: Identifiable {
        let mealType: String
        let dayIndex: Int
        var dishID: String?
        // dishID participates so replacing two different dishes in one slot
        // presents as two distinct sheets rather than reusing a stale one.
        var id: String { "\(mealType)-\(dayIndex)-\(dishID ?? "")" }
    }

    private var selectedDate: Date { weekContext.selectedDate }

    /// Localized single-letter weekday labels, ALWAYS Monday-first (the label is
    /// cosmetic; dayIndex 0 is always Monday in the plan). See LocalizedNames.
    private var dayLabels: [String] { LocalizedNames.veryShortWeekdayLabels() }

    private var calendar: Calendar { Calendar.current }
    private var currentWeekStart: Date { calendar.mondayOfWeek(containing: Date()) }
    private var displayedWeekStart: Date { weekContext.displayedWeekStart }
    private var displayedPlan: WeekPlan? { planStore.plan(for: displayedWeekStart) }
    private var isPastWeek: Bool { displayedWeekStart < currentWeekStart }

    private var selectedDayIndex: Int {
        calendar.dateComponents([.day], from: displayedWeekStart, to: selectedDate).day ?? 0
    }

    /// The latest navigable Monday: 4 weeks past the current week.
    private var maxWeekStart: Date {
        calendar.date(byAdding: .weekOfYear, value: 4, to: currentWeekStart) ?? currentWeekStart
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) else { return false }
        return calendar.mondayOfWeek(containing: next) <= maxWeekStart
    }

    /// Backward is allowed within the present/future, and into the past only
    /// for weeks that already exist in storage.
    private var canGoBackward: Bool {
        guard let previous = calendar.date(byAdding: .day, value: -1, to: selectedDate) else { return false }
        let previousWeekStart = calendar.mondayOfWeek(containing: previous)
        return previousWeekStart >= currentWeekStart || planStore.hasPlan(for: previousWeekStart)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                dateLine
                if isPastWeek {
                    pastWeekBadge
                }
                weekStrip

                switch generationState {
                case .generating:
                    // Synchronous and instant in practice, so this never renders
                    // (the state coalesces straight to .loaded/.failed). No
                    // spinner, no placeholder — just reserve the space.
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let error):
                    GenerationErrorView(
                        error: error,
                        onPrimaryAction: { handlePrimaryAction(for: error) },
                        onReport: { reportProblem(with: error) }
                    )
                    .transition(errorTransition)
                case .idle, .loaded:
                    // A plan's existence is the ground truth for the resting
                    // render, which keeps navigation correct across weeks.
                    if displayedPlan != nil {
                        // ONLY the planned week scrolls. A slot holds up to
                        // eight dishes, so the day's cards can outgrow the
                        // screen -- and before this they simply overflowed,
                        // clipping the header and pushing the grocery nudge
                        // under the tab bar.
                        //
                        // The header, date line, past-week badge and week strip
                        // stay OUTSIDE, pinned: the strip is navigation, and
                        // navigation that scrolls away is navigation you have to
                        // go looking for.
                        //
                        // The other three states stay outside too, because each
                        // one centers itself in the remaining height with
                        // Spacers -- inside a ScrollView those collapse and the
                        // content jumps to the top.
                        ScrollView {
                            // Same 14pt rhythm the outer VStack gave these
                            // children before they moved in here; the nudge's
                            // `.padding(.top, 2)` is measured against it.
                            VStack(spacing: 14) {
                                loadedContent
                            }
                            .padding(.bottom, 24)
                        }
                        // No rubber-band on a day whose cards already fit, so a
                        // short week still feels like a static screen.
                        .scrollBounceBehavior(.basedOnSize)
                    } else {
                        unplannedWeekState
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .spotlightScreen()
            .sheet(item: $pickerTarget) { target in
                let meal = displayedPlan?.meal(ofType: target.mealType, onDay: target.dayIndex)
                DishPickerView(
                    mealType: target.mealType,
                    mode: pickerMode(for: target, in: meal),
                    recipes: recipeStore.recipes,
                    preferences: preferencesStore.preferences,
                    selectedDishIDs: meal?.selectedIDs ?? [],
                    planCandidateIDs: meal?.unselectedCandidateIDs ?? []
                ) { ids in
                    apply(picked: ids, to: target)
                }
            }
            .sheet(item: $dishSelectionTarget) { target in
                if let meal = displayedPlan?.meal(ofType: target.mealType, onDay: target.dayIndex) {
                    DishSelectionSheet(
                        mealType: target.mealType,
                        // Resolved in candidate order; an id missing from the
                        // database (a deleted user recipe) simply drops out
                        // rather than rendering a blank row.
                        candidates: meal.candidateIDs.compactMap { recipe(withID: $0) },
                        initialSelection: meal.selectedIDs,
                        ratingsStore: ratingsStore
                    ) { ids in
                        applySelection(ids, to: target)
                    }
                }
            }
            .regenerateConfirmation(
                isPresented: $showRegenerateAlert,
                hasManualEdits: displayedPlan?.hasManualEdits == true
            ) {
                generateDisplayedWeek()
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }
            .sheet(item: $diagnosticShare) { share in
                // Reuses the feedback share path: plain text, "Meal Seek beta
                // feedback" subject for mail-type targets.
                ShareSheet(items: [FeedbackShareText(text: share.text)])
            }
            .toast($walkthroughToast)
            // Every gate below reports a change the user ALREADY made. None of
            // them cause a change, and the coordinator ignores anything that is
            // not the step it is waiting on.
            .onChange(of: weekContext.selectedDate) {
                walkthrough.report(.dayChanged)
            }
            .onChange(of: generationToken) {
                walkthrough.report(.weekRegenerated)
            }
            .onChange(of: displayedPlan?.meals) {
                walkthrough.report(.dishSelectionChanged)
            }
            // Fires on GENUINE completion only -- never on a skip, and never
            // off the sticky `hasCompletedWalkthrough` flag, which stays true
            // forever and so cannot distinguish a fresh completion from any
            // later moment.
            //
            // Checked on appear as well as on change because completion happens
            // on the ACCOUNT tab: the root switches back here, and this screen
            // may only become visible after the signal has already risen.
            .onChange(of: walkthrough.completionCount) { celebrateCompletionIfNeeded() }
            .onAppear { celebrateCompletionIfNeeded() }
            .onChange(of: displayedWeekStart) {
                // A stale error/warning/generating override belongs to the week
                // that produced it; reset to the new week's resting baseline.
                generationWarning = nil
                generationState = displayedPlan != nil ? .loaded : .idle
            }
            .overlay(alignment: .bottom) {
                if showShareFailedToast {
                    shareFailedToast
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.textPrimary)

            HStack(spacing: 10) {
                arrowButton(symbol: "chevron.left", enabled: canGoBackward) { step(by: -1) }
                Spacer()
                arrowButton(symbol: "chevron.right", enabled: canGoForward) { step(by: 1) }
                if showsShareButton {
                    shareButton
                }
                if showsRefreshButton {
                    refreshButton
                }
            }
        }
    }

    /// "Today" only on the actual current date; otherwise the weekday name.
    private var title: String {
        if calendar.isDateInToday(selectedDate) {
            return String(localized: "Today")
        }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }

    private var dateLine: some View {
        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .font(.system(size: 11))
            .foregroundStyle(.textTertiary)
    }

    private func arrowButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Color.textPrimary : Color(hex: "#D4D4D4"))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
    }

    /// Shown only for the current or a future week that already has a plan.
    private var showsRefreshButton: Bool {
        !isPastWeek && displayedPlan != nil
    }

    private var refreshButton: some View {
        Button {
            showRegenerateAlert = true
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandOrange))
        }
        .buttonStyle(PressableButtonStyle())
        .spotlightTarget(.reshuffle, cornerRadius: 10)
    }

    /// Shown whenever the displayed week has a plan — past weeks included;
    /// sharing history is harmless. Same geometry and treatment as the
    /// refresh button.
    private var showsShareButton: Bool {
        displayedPlan != nil
    }

    private var shareButton: some View {
        Button {
            shareDisplayedWeek()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandOrange))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var pastWeekBadge: some View {
        Text("Past week")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.textOnPale)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.brandOrangePale))
    }

    // MARK: Week strip

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let isSelected = index == selectedDayIndex
                Button {
                    selectDay(at: index)
                } label: {
                    Text(dayLabels[index])
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : .textOnPale)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(isSelected ? Color.brandOrange : .brandOrangePale))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .spotlightTarget(.seeWeek, cornerRadius: 22)
    }

    // MARK: Loaded week

    /// The banner (if any), the day's meal cards, and the grocery nudge. The
    /// banner and card list carry `.id(generationToken)` so a regeneration
    /// re-inits the subtree and replays the entrance cascade; `.transition(
    /// .identity)` keeps that re-init from cross-fading, leaving the movement to
    /// each element's own `entranceReveal`.
    @ViewBuilder
    private var loadedContent: some View {
        if let generationWarning {
            partialWarningBanner(generationWarning)
                .entranceReveal(
                    delay: EntranceTiming.bannerDelay(cardCount: PlanGenerator.mealTypes.count),
                    offsetY: EntranceTiming.bannerOffset,
                    reduceMotion: reduceMotion
                )
                .id(generationToken)
                .transition(.identity)
        }
        mealList
        if showsWalkthroughInvitation {
            walkthroughInvitationCard
                .padding(.top, 2)
        }
        if showsGroceryNudge {
            groceryNudgeCard
                .padding(.top, 2) // 14pt stack spacing + 2 = 16pt section gap
        }
    }

    // MARK: Meal cards

    @ViewBuilder
    private var mealList: some View {
        if let plan = displayedPlan {
            let types = PlanGenerator.mealTypes
            VStack(spacing: 12) {
                ForEach(Array(types.enumerated()), id: \.element) { index, mealType in
                    mealCard(for: mealType, in: plan)
                        .entranceReveal(
                            delay: EntranceTiming.cardDelay(index: index, count: types.count),
                            offsetY: EntranceTiming.cardOffset,
                            reduceMotion: reduceMotion
                        )
                }
            }
            .padding(.top, 6)
            .id(generationToken) // re-init per generation so the cascade replays
            .transition(.identity)
        }
    }

    /// One meal slot for the selected day: a filled card or an empty slot.
    ///
    /// Resolution is per DISH, not per slot: an id with no recipe behind it (a
    /// deleted user recipe) drops out and its siblings still render, matching
    /// what the share card and the grocery list already do. The empty state
    /// stands in only when NOTHING in the slot resolves. Keying off the slot's
    /// headline dish alone used to blank a whole card over one stale id.
    @ViewBuilder
    private func mealCard(for mealType: String, in plan: WeekPlan) -> some View {
        let meal = plan.meal(ofType: mealType, onDay: selectedDayIndex)
        let dishes = MealCardModel.dishes(for: meal, recipes: recipeStore.recipes)

        if let meal, !dishes.isEmpty {
            filledSlot(mealType: mealType, meal: meal, dishes: dishes)
        } else {
            // Past weeks are historical: the empty card is inert.
            EmptyMealSlotView(
                mealType: mealType,
                onAdd: isPastWeek ? nil : { openPicker(for: mealType) }
            )
        }
    }

    /// The error view's entrance/exit transition: a fade+scale, or a plain fade
    /// under Reduce Motion.
    private var errorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: EntranceTiming.errorScale).combined(with: .opacity)
    }

    /// A planned meal card: the slot's dishes, each with its own tap target and
    /// its own long-press menu.
    ///
    /// Nothing here wraps the whole card in a tap target. The card is a
    /// container; only its rows are interactive.
    @ViewBuilder
    private func filledSlot(mealType: String, meal: PlannedMeal, dishes: [Recipe]) -> some View {
        MealCardView(
            mealType: mealType,
            dishes: dishes,
            // No meal-type special-casing: breakfast's ceiling is 1, so a
            // breakfast slot is always full and never offers the row.
            canAddDish: !isPastWeek && meal.acceptsMoreDishes,
            isEditable: !isPastWeek,
            ratingsStore: ratingsStore,
            // Only the FIRST meal type carries it, so exactly one dish row on
            // the screen claims the step however many cards are showing.
            carriesDishMenuSpotlight: !isPastWeek && mealType == PlanGenerator.mealTypes.first,
            onAddDish: { openPicker(for: mealType) },
            onReplaceDish: { dishID in openPicker(replacing: dishID, in: mealType) },
            onRemoveDish: { dishID in removeDish(dishID, ofType: mealType) }
        )
    }

    private func recipe(withID id: String) -> Recipe? {
        recipeStore.recipes.first { $0.id == id }
    }

    // MARK: Grocery nudge

    /// Live unbought-item count for the displayed week, derived the same way
    /// the Grocery tab derives its list.
    private var unboughtGroceryCount: Int {
        guard let plan = displayedPlan else { return 0 }
        let items = ShoppingListBuilder.build(
            plan: plan,
            recipes: recipeStore.recipes,
            householdSize: preferencesStore.preferences.householdSize,
            pantryOverrides: preferencesStore.preferences.pantryOverrides
        )
        let bought = groceryStateStore.boughtNames(for: displayedWeekStart)
        return items.count { !bought.contains($0.id) }
    }

    /// Absent — not greyed out — on past weeks and once everything is bought.
    private var showsGroceryNudge: Bool {
        !isPastWeek && unboughtGroceryCount > 0
    }

    /// Switches to the Grocery tab (never pushes); the shared WeekContext
    /// guarantees the list is for the week being viewed here.
    private var groceryNudgeCard: some View {
        Button {
            selectedTab = .grocery
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.brandOrangePale)
                    Image(systemName: "cart.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.brandOrange)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Grocery list")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("\(unboughtGroceryCount) items left to buy")
                        .font(.system(size: 12))
                        .foregroundStyle(.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.backgroundCard)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 2)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Shows the completion toast once per genuine completion.
    private func celebrateCompletionIfNeeded() {
        guard walkthrough.completionCount > celebratedCompletionCount else { return }
        celebratedCompletionCount = walkthrough.completionCount
        withAnimation(.easeInOut(duration: 0.25)) {
            walkthroughToast = String(localized: "Your week's planned and your list is started.")
        }
    }

    // MARK: Walkthrough invitation

    /// Offered once, on Home, to a user who has never been through
    /// "Plan your first week" and has not waved it away.
    ///
    /// No red dot, no badge, no wiggle: an invitation, not a notification.
    private var showsWalkthroughInvitation: Bool {
        !preferencesStore.preferences.hasCompletedWalkthrough
            && !preferencesStore.preferences.hasDismissedWalkthroughInvitation
            && !walkthrough.isRunning
            && !isPastWeek
    }

    /// The grocery nudge's anatomy exactly: white card, 46pt pale tile, title 14
    /// semibold, subtitle 12 secondary, trailing chevron. Deliberately NOT a
    /// pale-orange surface -- text on pale must be `textOnPale` and pale
    /// surfaces carry no shadow, which would make this a different component
    /// sitting next to its twin.
    private var walkthroughInvitationCard: some View {
        HStack(spacing: 12) {
            Button {
                walkthrough.resume()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color.brandOrangePale)
                        Image(systemName: "sparkles")
                            .font(.system(size: 22))
                            .foregroundStyle(.brandOrange)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan your first week")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.textPrimary)
                        Text("Takes about a minute.")
                            .font(.system(size: 12))
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    preferencesStore.dismissWalkthroughInvitation()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.trailing, -12)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 2)
        )
    }

    // MARK: Partial-week warning

    /// A non-blocking notice above the meals when the week generated only
    /// partially. Pale surface, `textOnPale`, no shadow — per the design system
    /// for `brandOrangePale` surfaces.
    private func partialWarningBanner(_ warning: WeekGenerationWarning) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.textOnPale)
            Text(warning.userMessage)
                .font(.system(size: 13))
                .foregroundStyle(.textOnPale)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.brandOrangePale))
    }

    // MARK: Unplanned week

    private var unplannedWeekState: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("This week isn't planned yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.textSecondary)
            PrimaryButton(title: String(localized: "Plan this week")) {
                generateDisplayedWeek()
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: Actions

    private func step(by days: Int) {
        guard let destination = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            weekContext.selectedDate = calendar.startOfDay(for: destination)
        }
    }

    private func selectDay(at index: Int) {
        guard let destination = calendar.date(byAdding: .day, value: index, to: displayedWeekStart) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            weekContext.selectedDate = destination
        }
    }

    /// Fills an EMPTY slot: there is no dish to swap, so the whole-slot write is
    /// the correct one.
    private func openPicker(for mealType: String) {
        pickerTarget = MealSlotTarget(mealType: mealType, dayIndex: selectedDayIndex, dishID: nil)
    }

    /// Swaps one specific dish, leaving the slot's other dishes untouched.
    private func openPicker(replacing dishID: String, in mealType: String) {
        pickerTarget = MealSlotTarget(mealType: mealType, dayIndex: selectedDayIndex, dishID: dishID)
    }

    /// UNREFERENCED, retained deliberately. `DishSelectionSheet`'s function —
    /// reaching the generator's unselected candidates — moved into the picker's
    /// "FROM YOUR PLAN" section rather than living on as a second long-press
    /// target on the same card. Kept in place per additive-only until beta
    /// confirms the absorbed section; see PRE_LAUNCH.md.
    private func openDishSelection(for meal: PlannedMeal) {
        dishSelectionTarget = MealSlotTarget(mealType: meal.mealType, dayIndex: meal.dayIndex)
    }

    /// Commits a confirmed selection and persists it. `setSelection` refuses an
    /// empty or fully-invalid set, so a rejected edit leaves the plan alone
    /// instead of emptying the slot.
    private func applySelection(_ ids: [String], to target: MealSlotTarget) {
        guard var plan = displayedPlan else { return }
        guard plan.setSelection(ids, ofType: target.mealType, onDay: target.dayIndex) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            planStore.save(plan)
        }
    }

    /// Drops ONE dish immediately — no confirmation — and logs the rejection.
    ///
    /// Removing the slot's last dish empties the slot, which renders as the
    /// dashed "+ Add meal" state; `WeekPlan.removeDish` handles that transition,
    /// so there is no separate whole-slot path to keep in step. The 0.3s ease is
    /// slower than the app's usual 0.25 on purpose: the user needs to see WHICH
    /// row left a list of otherwise identical rows.
    private func removeDish(_ dishID: String, ofType mealType: String) {
        guard var plan = displayedPlan else { return }
        guard plan.removeDish(dishID, ofType: mealType, onDay: selectedDayIndex) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            planStore.save(plan)
        }
        FeedbackLogger.log(FeedbackEvent(
            recipeId: dishID,
            mealType: mealType,
            action: .removed,
            date: Date(),
            weekStartDate: plan.weekStartDate
        ))
    }

    /// The picker's mode for a target: swapping a named dish, or adding under
    /// whatever budget the slot's current dish count leaves.
    private func pickerMode(for target: MealSlotTarget, in meal: PlannedMeal?) -> DishPickerView.Mode {
        if let dishID = target.dishID {
            return .replace(dishID: dishID)
        }
        return .add(budget: PlanGenerator.addBudget(
            for: target.mealType,
            currentDishCount: meal?.dishCount ?? 0
        ))
    }

    /// Writes the picker's result into the target slot, persists, and logs the
    /// swap signals.
    ///
    /// Three distinct writes, and the distinction is the whole point:
    ///
    /// - REPLACE edits one dish in place, leaving the slot's other dishes and
    ///   their order alone. Routing this through the whole-slot write is what
    ///   used to collapse a multi-dish slot to a single recipe.
    /// - ADD appends to an existing slot, under the meal type's ceiling.
    /// - FILL creates a slot that did not exist. It passes an EMPTY candidate
    ///   set, because the generator offered nothing here — every dish in a
    ///   hand-filled slot is a manual one, so removing it later deletes it
    ///   outright instead of leaving it re-selectable under an offer that was
    ///   never made.
    private func apply(picked ids: [String], to target: MealSlotTarget) {
        guard var plan = displayedPlan, let first = ids.first else { return }

        let outgoingID: String?
        if let dishID = target.dishID {
            guard plan.replaceDish(dishID, with: first,
                                   ofType: target.mealType, onDay: target.dayIndex) else { return }
            outgoingID = dishID
        } else if plan.meal(ofType: target.mealType, onDay: target.dayIndex) != nil {
            guard plan.addDishes(ids, ofType: target.mealType, onDay: target.dayIndex) else { return }
            outgoingID = nil
        } else {
            plan.setMeal(recipeID: first, ofType: target.mealType, onDay: target.dayIndex,
                         candidateIDs: [], selectedIDs: ids)
            outgoingID = nil
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            planStore.save(plan)
        }

        // Log what actually landed, not what was picked: a bulk add can be
        // trimmed by the ceiling, and a feedback signal for a dish that never
        // entered the plan would be a false positive.
        let landed = plan.meal(ofType: target.mealType, onDay: target.dayIndex)?.selectedIDs ?? []
        var events: [FeedbackEvent] = []
        if let outgoingID {
            events.append(FeedbackEvent(
                recipeId: outgoingID,
                mealType: target.mealType,
                action: .replacedAway,
                date: Date(),
                weekStartDate: plan.weekStartDate
            ))
        }
        for id in ids where landed.contains(id) {
            events.append(FeedbackEvent(
                recipeId: id,
                mealType: target.mealType,
                action: .added,
                date: Date(),
                weekStartDate: plan.weekStartDate
            ))
        }
        FeedbackLogger.log(events)
    }

    /// Renders the displayed week's share card and presents the share sheet.
    /// Synchronous: rasterizing the static card takes well under a frame, so
    /// there is no spinner and no background hop. If rendering fails, a brief
    /// toast — never an empty share sheet.
    private func shareDisplayedWeek() {
        guard let plan = displayedPlan else { return }
        if let image = ShareCardRenderer.render(
            plan: plan,
            recipes: recipeStore.recipes,
            translations: translations
        ) {
            shareItem = ShareCardImage(image: image)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { showShareFailedToast = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeInOut(duration: 0.25)) { showShareFailedToast = false }
            }
        }
    }

    /// Same anatomy as Account's copied-address toast.
    private var shareFailedToast: some View {
        Text("Couldn't create the share image")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.textOnPale)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.brandOrangePale))
            .padding(.bottom, 16)
            .transition(.opacity)
    }

    /// Generates (or regenerates) the displayed week and persists it. Only
    /// ever called from an explicit user action.
    ///
    /// Regenerate replaces the plan wholesale and must never emit
    /// FeedbackEvents — a reshuffle is not a dislike signal. Do not
    /// reimplement this as a loop of removeMeal calls.
    private func generateDisplayedWeek() {
        // A real state, but generation is synchronous and instant, so it
        // coalesces straight to the result below and never renders — no spinner,
        // no artificial delay.
        generationState = .generating

        let outcome = PlanGenerator.generate(
            recipes: recipeStore.recipes,
            preferences: preferencesStore.preferences,
            ratings: ratingsStore.ratings,
            weekStartDate: displayedWeekStart,
            databaseLoadFailureReason: recipeStore.loadFailureReason
        )

        switch outcome {
        case .success(let success):
            planStore.save(success.plan)
            generationWarning = success.warning
            // New identity → the day-card subtree re-inits and the cascade
            // replays, even when regenerating a week already on screen.
            generationToken &+= 1
            withAnimation(loadedTransitionAnimation) {
                generationState = .loaded
            }
        case .failure(let error):
            // Keep any previously saved plan in storage untouched (we only
            // overwrite on success) and surface the designed error state.
            generationWarning = nil
            withAnimation(failedTransitionAnimation) {
                generationState = .failed(error)
            }
        }
    }

    /// Governs the outgoing branch when a result resolves; the incoming cards
    /// animate themselves via `entranceReveal`.
    private var loadedTransitionAnimation: Animation {
        .easeInOut(duration: reduceMotion ? EntranceTiming.reduceMotionFade : 0.25)
    }

    private var failedTransitionAnimation: Animation {
        .easeInOut(duration: reduceMotion ? EntranceTiming.reduceMotionFade : EntranceTiming.errorDuration)
    }

    /// The error screen's primary button: loosen settings, or retry.
    private func handlePrimaryAction(for error: WeekGenerationError) {
        switch error.primaryAction {
        case .adjustPreferences:
            selectedTab = .account
        case .tryAgain:
            generateDisplayedWeek()
        }
    }

    /// The error screen's "Report this problem": assemble the diagnostic and
    /// present it through the existing share-sheet flow.
    private func reportProblem(with error: WeekGenerationError) {
        let report = DiagnosticReport.forGenerationFailure(
            error: error,
            recipes: recipeStore.recipes,
            preferences: preferencesStore.preferences
        )
        diagnosticShare = FeedbackShare(text: report.text)
    }
}
