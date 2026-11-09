//
//  WalkthroughCoordinator.swift
//  Meal Seek
//
//  Runs "Plan your first week": which step is showing, when it advances, and
//  what is remembered across launches.
//
//  The coordinator NEVER writes plan data. It observes real changes the user
//  made and moves the spotlight; every gate here is a report that something
//  already happened, not a request for it to happen.
//

import SwiftUI

@Observable
final class WalkthroughCoordinator {
    /// The step being shown, or nil when the walkthrough is not running.
    private(set) var step: WalkthroughStep?

    /// True once the step's gate has fired and it is waiting for the user to
    /// switch tabs. The spotlight has moved to the tab item; the step has not
    /// advanced yet.
    private(set) var isHandingOff = false

    /// Set when a step with a `fallbackNextAfter` has waited long enough, so its
    /// card can offer a way out.
    private(set) var fallbackAvailable = false

    /// True while a step's target is being scrolled into view.
    ///
    /// The overlay draws NO cutout during this window. Without it the hole
    /// chases the row across the screen for 0.25s, which looks like a bug and
    /// invites a tap at a moving target.
    private(set) var isPreparing = false

    /// Raised once per GENUINE completion. Skips never touch it.
    ///
    /// A monotonic counter rather than a Bool, so it is an explicit one-shot
    /// EVENT rather than a state anyone has to reset or clear. Observers compare
    /// it against the last value they acted on, which means:
    ///   - it fires again on a replay (deliberate: a replay was asked for, and
    ///     withholding the payoff reads as broken),
    ///   - it cannot be missed by an observer that was off screen when it rose,
    ///   - and nothing reads a flag that the same call stack is still writing.
    private(set) var completionCount = 0

    var isRunning: Bool { step != nil }

    /// Where completion and progress are written. Nil in previews and tests, in
    /// which case the walkthrough runs but remembers nothing.
    private let preferencesStore: PreferencesStore?

    private var fallbackTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    init(preferencesStore: PreferencesStore? = nil) {
        self.preferencesStore = preferencesStore
    }

    // MARK: Running

    /// Starts from the beginning. Used by both entry points -- the Home
    /// invitation and the Account row -- because a replay that resumed halfway
    /// would be baffling to someone who chose to watch it again.
    func start() {
        show(.seeWeek)
    }

    /// Resumes an interrupted run, or starts a new one.
    func resume() {
        let saved = preferencesStore?.preferences.walkthroughLastStep
        show(saved.flatMap(WalkthroughStep.init(rawValue:)) ?? .seeWeek)
    }

    private func show(_ next: WalkthroughStep) {
        fallbackTask?.cancel()
        prepareTask?.cancel()
        fallbackAvailable = false
        isHandingOff = false
        // Scroll first, draw second. A screen hosting the target answers by
        // observing `isPreparing`; screens with nothing to scroll simply do
        // nothing and the window elapses harmlessly.
        isPreparing = next.needsScrollIntoView
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
        preferencesStore?.setWalkthroughLastStep(next.rawValue)
        if isPreparing {
            prepareTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self, self.step == next else { return }
                withAnimation(.easeInOut(duration: 0.2)) { self.isPreparing = false }
                self.scheduleFallbackIfNeeded(for: next)
            }
        } else {
            scheduleFallbackIfNeeded(for: next)
        }
    }

    /// A step whose gate the user may have no reason to satisfy gets an escape
    /// hatch after a delay, rather than a permanent one that invites skipping
    /// the interaction it is teaching.
    private func scheduleFallbackIfNeeded(for step: WalkthroughStep) {
        guard let delay = step.fallbackNextAfter else { return }
        // @MainActor on the task body, and one strong unwrap inside it: the
        // previous shape captured `self?` across a concurrency boundary, which
        // is a warning today and an error under Swift 6.
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.step == step else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.fallbackAvailable = true }
        }
    }

    /// Leaves the walkthrough. Skipping always exits the WHOLE run -- one tap
    /// gets the user their app back -- and marks it done so it does not ambush
    /// them again.
    func skip() {
        finish(didComplete: false)
    }

    /// The user reached the end.
    func complete() {
        finish(didComplete: true)
    }

    /// Ends the run.
    ///
    /// `didComplete` is what separates finishing from skipping, and the two must
    /// diverge: BOTH set the sticky "do not offer this again" flag, but only a
    /// genuine completion raises `completionCount`. Reading the sticky flag to
    /// decide whether to celebrate cannot work -- it stays true forever, so it
    /// can never tell a fresh completion from any later moment.
    private func finish(didComplete: Bool) {
        fallbackTask?.cancel()
        fallbackTask = nil
        prepareTask?.cancel()
        prepareTask = nil
        isPreparing = false
        fallbackAvailable = false
        isHandingOff = false
        withAnimation(.easeInOut(duration: 0.25)) { step = nil }
        // Sticky, on both paths: a skip still means "stop offering this".
        preferencesStore?.markWalkthroughComplete()
        if didComplete { completionCount += 1 }
    }

    // MARK: Advancing

    /// Called when a real state change happens somewhere in the app.
    ///
    /// Ignores anything that is not the current step's gate, so a user who
    /// regenerates their week during step 5 simply regenerates their week.
    func report(_ gate: WalkthroughStep.Gate) {
        guard let step, !isHandingOff, step.advancesOn == gate else { return }
        advancePastCurrentStep()
    }

    /// The coach card's "Next", on the two steps that have nothing to do, and on
    /// a step whose fallback has become available.
    func confirmStep() {
        guard step != nil, !isHandingOff else { return }
        advancePastCurrentStep()
    }

    private func advancePastCurrentStep() {
        guard let step else { return }
        // A step that hands off does not advance yet: the spotlight moves to the
        // tab item and waits for the user to actually go there.
        if step.handoff != nil {
            fallbackTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { isHandingOff = true }
            return
        }
        moveOn(from: step)
    }

    /// Called when the user switches tabs, which is what completes a handoff.
    func report(tabChangedTo tab: AppTab) {
        guard let step, isHandingOff, step.handoff == tab else { return }
        moveOn(from: step)
    }

    private func moveOn(from step: WalkthroughStep) {
        if let next = step.next {
            show(next)
        } else {
            complete()
        }
    }

    // MARK: Card content

    /// The message for the current state -- a handing-off step says where to go
    /// next instead of repeating what was just learned.
    var currentMessage: LocalizedStringKey? {
        guard let step else { return nil }
        if isHandingOff, let handoffMessage = step.handoffMessage { return handoffMessage }
        return step.message
    }

    /// Whether the card should offer "Next" right now.
    var showsNext: Bool {
        guard let step, !isHandingOff else { return false }
        return step.isNonAction || fallbackAvailable
    }
}

// MARK: Environment

extension EnvironmentValues {
    /// The default is a NOT-RUNNING coordinator rather than nil, so
    /// `.spotlightTarget` needs no optional dance and any view can be previewed
    /// or hosted outside the walkthrough without special-casing.
    @Entry var walkthrough = WalkthroughCoordinator()
}
