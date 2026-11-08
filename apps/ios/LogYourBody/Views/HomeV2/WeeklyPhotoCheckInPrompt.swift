//
// WeeklyPhotoCheckInPrompt.swift
// LogYourBody
//
import SwiftUI

/// One dismissible weekly photo action. It does not replace the check-in dock,
/// and it stays hidden once this week already has a diary photo.
struct WeeklyPhotoCheckInPrompt: View {
    let prompt: WeeklyPhotoCheckInPolicy.Prompt
    let onAdd: () -> Void

    @AppStorage(WeeklyPhotoCheckInPolicy.dismissedWeekDefaultsKey) private var dismissedWeek = ""

    var body: some View {
        if dismissedWeek != prompt.weekKey {
            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                Text(prompt.title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(prompt.message)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: HomeV2Tokens.Space.row) {
                    Button(prompt.actionTitle, action: onAdd)
                        .buttonStyle(.plain)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .frame(minHeight: JovieTokens.minimumHitTarget)
                        .accessibilityIdentifier("weekly_photo_check_in_add")
                    Button(prompt.dismissTitle) { dismissedWeek = prompt.weekKey }
                        .buttonStyle(.plain)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(minHeight: JovieTokens.minimumHitTarget)
                        .accessibilityIdentifier("weekly_photo_check_in_dismiss")
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.vertical, HomeV2Tokens.Space.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weekly_photo_check_in_prompt")
        }
    }
}
