//
//  WeekShareCard.swift
//  Meal Seek
//
//  The shareable week image: a fixed 360×640pt (9:16) portrait card rendered
//  off-screen at 3x by ShareCardRenderer — never pushed or presented as a
//  screen. Branding (mark, wordmark, slogan), the week's date range, and all
//  21 slots grouped by day. Meals are text rows with the fixed meal-type
//  glyphs: 21 RecipeSymbol tiles at this scale would put the motif art below
//  legibility, so the card is deliberately text-only.
//

import SwiftUI

struct WeekShareCard: View {
    let plan: WeekPlan
    let recipes: [Recipe]
    /// Passed in explicitly (not read from the environment): ImageRenderer builds
    /// this view outside the app's SwiftUI environment, so an `@Environment`
    /// store would be the inert English default. See ShareCardRenderer.render.
    let translations: RecipeTranslationStore

    /// Design canvas in points; ShareCardRenderer rasterizes at 3x for
    /// 1080×1920 output at the minimum height.
    ///
    /// The width is fixed. The height is a FLOOR, not a fixed size: a lunch or
    /// dinner slot renders one line per selected dish, so a week where several
    /// slots hold 3–4 dishes needs more vertical room than 9:16 provides. The
    /// card grows to fit rather than clipping, and a light week — every slot one
    /// dish — still renders at exactly 360×640, identical to before.
    static let size = CGSize(width: 360, height: 640)

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    dayRow(dayIndex)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        // Width fixed, height a minimum: SwiftUI measures the real content and
        // the image grows past 640 only when the dishes need it. Setting an
        // exact height here is what would clip a dense week, so don't.
        .frame(width: Self.size.width)
        .frame(minHeight: Self.size.height, alignment: .top)
        .background(Color.backgroundPrimary)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            markTile

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Meal Seek")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                Text("Plan once. Eat all week.")
                    .font(.system(size: 12))
                    .foregroundStyle(.textSecondary)
            }

            Spacer(minLength: 8)

            Text(dateRange)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.textOnPale)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.brandOrangePale))
        }
    }

    /// The bowl-and-spoon app icon, clipped to the icon-tile radius ratio.
    /// There is no standalone transparent mark asset, but the icon itself is
    /// the mark on flat brand orange, so clipping it reproduces it exactly.
    /// Falls back to the Welcome-tile treatment if the asset can't load.
    @ViewBuilder
    private var markTile: some View {
        if let icon = UIImage(named: "AppIcon") {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 44 * 13 / 46))
        } else {
            RoundedRectangle(cornerRadius: 44 * 13 / 46)
                .fill(Color.brandOrange)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: SFSymbols.chefHat)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }

    /// "Jul 13 – Jul 19" for the plan's Monday-started week.
    private var dateRange: String {
        let start = plan.weekStartDate
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    // MARK: Day rows

    private func dayRow(_ dayIndex: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedNames.shortWeekdayLabels()[dayIndex].uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.brandOrange)
                Text(dayNumber(dayIndex))
                    .font(.system(size: 11))
                    .foregroundStyle(.textTertiary)
            }
            .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: slotSpacing) {
                ForEach(PlanGenerator.mealTypes, id: \.self) { mealType in
                    mealLines(mealType: mealType, dayIndex: dayIndex)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundCard)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        )
    }

    private func dayNumber(_ dayIndex: Int) -> String {
        guard let date = calendar.date(byAdding: .day, value: dayIndex, to: plan.weekStartDate) else {
            return ""
        }
        return date.formatted(.dateTime.day())
    }

    /// Glyph column width and the gap to the text, shared by the first line of a
    /// slot and the hanging indent of its continuation lines.
    private static let glyphWidth: CGFloat = 12
    private static let glyphGap: CGFloat = 6

    /// True once any slot in the week holds more than one selected dish.
    private var hasMultiDishSlot: Bool {
        plan.meals.contains { $0.selectedIDs.count > 1 }
    }

    /// Vertical rhythm inside a day, in three tiers: wrapped lines of one dish
    /// name sit flush (0), dishes within a slot get `dishSpacing`, and the three
    /// slots get `slotSpacing`. Each tier must be visibly larger than the one
    /// below or the card stops parsing — a wrapped second line of a Spanish dish
    /// name would read as the start of the next dish.
    ///
    /// While every slot is a single dish there is nothing to disambiguate, so
    /// both collapse to the original 2pt and a light week renders at the
    /// pre-candidates size. All values are on the design system's micro scale.
    private var dishSpacing: CGFloat { hasMultiDishSlot ? 4 : 2 }
    private var slotSpacing: CGFloat { hasMultiDishSlot ? 8 : 2 }

    /// One meal slot: every dish the user selected, one per line, or an
    /// unobtrusive placeholder line — an empty slot never leaves a hole.
    ///
    /// The meal-type glyph marks the FIRST line only; the rest hang indented to
    /// the text column, so a four-dish dinner reads as one slot with four dishes
    /// rather than four separate meals. The glyph stays fixed per meal type and
    /// never varies per recipe.
    private func mealLines(mealType: String, dayIndex: Int) -> some View {
        let isEmpty = plan.meal(ofType: mealType, onDay: dayIndex)
            .map { meal in !meal.selectedIDs.contains { id in recipes.contains { $0.id == id } } }
            ?? true
        let labels = WeekShareCardModel.mealLabels(
            for: mealType, onDay: dayIndex,
            in: plan, recipes: recipes,
            translations: translations,
            emptyPlaceholder: String(localized: "No meal planned")
        )

        return VStack(alignment: .leading, spacing: dishSpacing) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: Self.glyphGap) {
                    if index == 0 {
                        Image(systemName: MealTypeIcon.symbol(for: mealType))
                            .font(.system(size: 9))
                            .foregroundStyle(isEmpty ? .textTertiary : .brandOrange)
                            .frame(width: Self.glyphWidth)
                    } else {
                        Color.clear
                            .frame(width: Self.glyphWidth, height: 0)
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isEmpty ? .textTertiary : .textPrimary)
                        // Two lines, not one. Measured across all 647 names at
                        // 11pt medium against this column's 232pt: Spanish
                        // overflows one line for 40 names (6.2%, longest
                        // 312.7pt) and English for 2; NO name in any of the
                        // three languages exceeds two lines. So this is the
                        // smallest limit that truncates nothing anywhere —
                        // one line visibly clipped Spanish with an ellipsis.
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Rasterizes the card. Synchronous and fast (a static 360×640 view, no
/// images beyond the icon); called on the main actor because ImageRenderer
/// requires it.
enum ShareCardRenderer {
    @MainActor
    static func render(
        plan: WeekPlan,
        recipes: [Recipe],
        translations: RecipeTranslationStore
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: WeekShareCard(plan: plan, recipes: recipes, translations: translations)
        )
        renderer.scale = 3
        // Width pinned, height UNSPECIFIED so the card reports its own natural
        // height. Proposing a concrete 640 here would squeeze a dense week back
        // into 9:16 and clip the dishes the card exists to show; the view's own
        // `minHeight` keeps a light week at exactly 360×640.
        renderer.proposedSize = ProposedViewSize(width: WeekShareCard.size.width, height: nil)
        return renderer.uiImage
    }
}

/// The rendered card wrapped for `.sheet(item:)` presentation.
struct ShareCardImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The system share sheet, handed its items directly (the week-card UIImage,
/// the feedback text) so every accepting target works unmodified.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Runs once the share sheet finishes (shared, saved, or cancelled). The
    /// data-backup export uses it to delete its temporary file; existing
    /// callers omit it. Defaulted so the week-card and feedback shares are
    /// unaffected.
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
