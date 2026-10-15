//
// HomeV2ContextView.swift
// LogYourBody
//
import SwiftUI

/// Context (Pencil N2): the selected day. Month, week strip, the day's
/// photos, entries with provenance, the note, and one action.
struct HomeV2ContextView: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedDay: Date
    let detail: (Date) -> HomeV2DayDetail
    let onClose: () -> Void
    let onEditEntry: (BodyMetrics) -> Void
    let onLogWeight: (Date) -> Void
    let onAddPhoto: (BodyMetrics) -> Void
    let onOpenPhoto: (BodyMetrics) -> Void
    var now = Date()

    private let calendar = Calendar.current
    private static let photoSize = CGSize(width: 135, height: 200)
    private static let addSlotWidth: CGFloat = 72

    private var day: HomeV2DayDetail { detail(selectedDay) }
    private var week: [Date] { HomeV2WeekStrip.days(containing: selectedDay, calendar: calendar) }
    private var daysWithEntries: Set<Date> { Set(bodyMetrics.map { calendar.startOfDay(for: $0.date) }) }
    private var isFutureDay: Bool { calendar.startOfDay(for: selectedDay) > calendar.startOfDay(for: now) }

    var body: some View {
        let day = day
        VStack(spacing: 0) {
            header
            weekStrip

            ScrollView {
                VStack(alignment: .leading, spacing: HomeV2Tokens.Space.row) {
                    photos(day)
                    entries(day)
                    if let note = day.note {
                        noteRow(note)
                    }
                }
                .padding(.top, HomeV2Tokens.Space.tight)
            }

            dock(day)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            Text(HomeV2ContextCopy.monthTitle(for: selectedDay, now: now, calendar: calendar))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .bold, relativeTo: .title2)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home_v2_context")

            Spacer(minLength: HomeV2Tokens.Space.tight)

            Button(action: onClose) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Today")
            .accessibilityIdentifier("home_v2_context_close")
        }
        .padding(.leading, HomeV2Tokens.Space.inset)
        .padding(.trailing, HomeV2Tokens.Space.row)
        .frame(minHeight: JovieTokens.compactControlHeight)
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { date in
                dayCell(date)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .padding(.vertical, HomeV2Tokens.Space.tight)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shiftWeek(by: value.translation.width < 0 ? 7 : -7)
            }
        )
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
        let hasEntry = daysWithEntries.contains(calendar.startOfDay(for: date))
        let dayNumber = calendar.component(.day, from: date)

        return Button {
            selectedDay = date
            HapticManager.shared.selection()
        } label: {
            VStack(spacing: HomeV2Tokens.Space.tight / 2) {
                Text(HomeV2WeekStrip.weekdayLetter(for: date, calendar: calendar))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Text("\(dayNumber)")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(isFuture ? HomeV2Tokens.Colors.quiet : HomeV2Tokens.Colors.ink)
                Circle()
                    .fill(hasEntry ? HomeV2Tokens.Colors.ion : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: JovieTokens.minimumHitTarget, height: 58)
            .background(
                isSelected ? HomeV2Tokens.Colors.card : Color.clear,
                in: RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HomeV2ContextCopy.dayFormatter.string(from: date))
        .accessibilityValue(hasEntry ? "Has an entry" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("home_v2_context_day_\(dayNumber)")
    }

    private func shiftWeek(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        selectedDay = next
        HapticManager.shared.selection()
    }

    @ViewBuilder
    private func photos(_ day: HomeV2DayDetail) -> some View {
        if day.photoURL != nil || day.metric != nil {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                if let photoURL = day.photoURL, let metric = day.metric {
                    Button {
                        onOpenPhoto(metric)
                    } label: {
                        SubjectPlateView(urlString: photoURL, size: Self.photoSize)
                            .clipShape(RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Progress photo")
                    .accessibilityHint("Opens the photo")
                    .accessibilityIdentifier("home_v2_context_photo")
                }

                if let metric = day.metric, !isFutureDay {
                    Button {
                        onAddPhoto(metric)
                    } label: {
                        VStack(spacing: HomeV2Tokens.Space.tight) {
                            Image(systemName: "camera")
                                .font(.system(size: 20, weight: .medium))
                            Text(HomeV2ContextCopy.addPhoto)
                                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        }
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(width: Self.addSlotWidth, height: Self.photoSize.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous)
                                .stroke(HomeV2Tokens.Colors.borderStrong, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a photo for this day")
                    .accessibilityIdentifier("home_v2_context_add_photo")
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.compact)
        }
    }

    private func entries(_ day: HomeV2DayDetail) -> some View {
        VStack(spacing: 0) {
            if day.rows.isEmpty {
                Text(HomeV2ContextCopy.nothingLogged)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .overlay(alignment: .bottom) { HomeV2Hairline() }
                    .accessibilityIdentifier("home_v2_context_empty")
            }

            ForEach(day.rows) { row in
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        Text(row.subline)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    }

                    Spacer(minLength: HomeV2Tokens.Space.tight)

                    Text(row.value)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, HomeV2Tokens.Space.inset)
                .frame(minHeight: 64)
                .overlay(alignment: .bottom) { HomeV2Hairline() }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home_v2_context_row_\(row.id)")
            }
        }
        .overlay(alignment: .top) { HomeV2Hairline() }
    }

    private func noteRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: HomeV2Tokens.Space.row) {
            Image(systemName: "note.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
            Text(note)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .accessibilityIdentifier("home_v2_context_note")
    }

    @ViewBuilder
    private func dock(_ day: HomeV2DayDetail) -> some View {
        if let metric = day.metric {
            HomeV2Dock(title: HomeV2ContextCopy.editEntry, identifier: "home_v2_edit_entry") {
                onEditEntry(metric)
            }
        } else if !isFutureDay {
            HomeV2Dock(title: HomeV2Copy.logWeight, identifier: "home_v2_log_weight_day") {
                onLogWeight(selectedDay)
            }
        }
    }
}
