import SwiftUI

struct TrainingExerciseHistoryRow: View {
    let exerciseId: String
    @ObservedObject var model: TrainingProgressModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            if let progress = model.response?.progress {
                if let exercise = progress.exercises.first(where: { $0.exerciseId == exerciseId }) {
                    Text("Last recorded · \(trainingHistoryDate(exercise.lastPerformedAt))")
                        .font(.footnote.weight(.medium))
                    ForEach(exercise.lastSession) { set in
                        Text("Set \(set.setNumber): \(set.performanceText)\(set.corrections?.isEmpty == false ? " · corrected" : "")")
                    }
                    if let heaviest = exercise.heaviestSet {
                        Text("Heaviest recorded: \(heaviest.performanceText)")
                    }
                } else {
                    Text("No recorded sets for this exercise yet.")
                }
            } else {
                Text(model.errorMessage == nil ? "Loading exercise history…" : "Exercise history unavailable.")
            }
        }
        .font(.footnote)
        .foregroundStyle(theme.colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("training_history_\(exerciseId)")
    }
}

struct TrainingProgressReviewSection: View {
    @ObservedObject var model: TrainingProgressModel
    let decision: TrainingProgressDecision?
    let retry: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            if let progress = model.response?.progress {
                ProgressReviewCard(progress: progress, decision: model.errorMessage == nil ? decision : nil)
            }
            if model.isLoading {
                ProgressView("Refreshing history…")
                    .font(.footnote)
                    .accessibilityIdentifier("training_history_loading")
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityIdentifier("training_history_error")
                Button("Retry history", action: retry)
                    .frame(minHeight: JovieTokens.minimumHitTarget)
                    .accessibilityIdentifier("training_history_retry")
            }
        }
    }
}

struct ProgressReviewCard: View {
    let progress: TrainingProgress
    let decision: TrainingProgressDecision?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text("Progress review")
                .font(.headline)
            Text("\(progress.completedSessions) sessions completed · \(progress.setsLast7Days) sets in the last 7 days")
                .font(.subheadline)
            if let feedback = progress.latestCheckIn {
                TrainingHistoryFeedbackRow(feedback: feedback)
            }
            if progress.sessions.isEmpty {
                Text("Your recorded results and check-ins will appear here.")
            } else {
                DisclosureGroup("Recorded results and check-ins") {
                    ForEach(progress.sessions) { session in
                        TrainingSessionHistoryRow(session: session)
                    }
                }
                .accessibilityIdentifier("training_review_records")
            }
            if let decision {
                engineReview(decision)
            } else {
                Text("Engine review is unavailable. Refresh your training session to try again.")
            }
        }
        .font(.footnote)
        .foregroundStyle(theme.colors.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
        .accessibilityIdentifier("training_progress_review_card")
    }

    private func engineReview(_ receipt: TrainingProgressDecision) -> some View {
        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            Text(receipt.decision.requiresConfirmation == true ? "Proposed change · confirmation required" : "Engine review")
                .font(.subheadline.weight(.medium))
            if receipt.hasMeaningfulChange {
                Text("Before: \(receipt.before)")
                Text("Next: \(receipt.after)")
                Text(receipt.rationale)
                    .accessibilityIdentifier("training_review_change_reason")
            }
            Text(receipt.nextAction)
                .accessibilityIdentifier("training_review_next_action")
            Text("Review: \(receipt.reviewPoint)")
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}

private struct TrainingSessionHistoryRow: View {
    let session: TrainingProgress.SessionHistory
    @Environment(\.theme) private var theme

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
                ForEach(session.skippedExerciseNames, id: \.self) { name in
                    Text("Skipped: \(name)")
                }
                ForEach(session.sets) { set in
                    let name = session.prescription?.exercises.first { $0.id == set.exerciseId }?.name
                        ?? session.initialPrescription?.exercises.first { $0.id == set.exerciseId }?.name
                        ?? set.exerciseId
                    Text("\(name), set \(set.setNumber): \(set.performanceText)")
                    if set.corrections?.isEmpty == false {
                        Text("Corrected result")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                ForEach(session.feedback) { feedback in
                    TrainingHistoryFeedbackRow(feedback: feedback)
                    if session.feedback.contains(where: { $0.correctsObservationId == feedback.id }) {
                        Text("Superseded by a corrected check-in")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                if session.feedback.isEmpty {
                    Text("No check-in recorded for this session.")
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
                Text(session.prescription?.title ?? "Training session")
                Text("\(session.statusText) · \(trainingHistoryDate(session.startedAt ?? session.completedAt))")
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityIdentifier("training_history_session_\(session.id)")
    }
}

private struct TrainingHistoryFeedbackRow: View {
    let feedback: TrainingProgress.Feedback

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            Text("Reported check-in · \(feedback.source ?? "unknown source") · \(trainingHistoryDate(feedback.observedAt ?? feedback.createdAt))")
            if let statement = feedback.originalStatement { Text(statement) }
            if let value = feedback.performance { Text("Reported performance: \(value)") }
            if let value = feedback.soreness { Text("Reported soreness: \(value)/10") }
            if let value = feedback.jointPain { Text("Reported joint pain: \(value)/10") }
            if let value = feedback.targetMuscleReadiness { Text("Target muscle readiness: \(value)") }
            if let value = feedback.generalReadiness { Text("General readiness: \(value)") }
            if let value = feedback.breathingReadiness { Text("Breathing readiness: \(value)") }
            if let value = feedback.supportingReadiness?.grip { Text("Grip readiness: \(value)") }
            if let value = feedback.supportingReadiness?.trunk { Text("Trunk readiness: \(value)") }
            ForEach((feedback.muscles ?? [:]).keys.sorted(), id: \.self) { muscle in
                if let observation = feedback.muscles?[muscle] {
                    if let value = observation.recovery { Text("\(muscle) recovery: \(value)") }
                    if let value = observation.performance { Text("\(muscle) reported performance: \(value)") }
                    if let value = observation.soreness { Text("\(muscle) reported soreness: \(value)/10") }
                }
            }
            if let value = feedback.trunkFatigue { Text("Reported trunk fatigue: \(value)/10") }
            if let value = feedback.pump { Text("Reported pump: \(value)/10") }
            if feedback.correctsObservationId != nil { Text("Correction to an earlier check-in") }
            if feedback.transcriptionUncertain == true { Text("Transcription uncertain") }
        }
        .accessibilityIdentifier("training_history_feedback_\(feedback.id)")
    }
}

private func trainingHistoryDate(_ value: String?) -> String {
    guard let value else { return "date unknown" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: value)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: value)
    }
    return date?.formatted(date: .abbreviated, time: .omitted) ?? "date unknown"
}

/// The native adapter renders compiled views from owned domain data, never a generated view tree.
struct ApprovedTrainingCard<Content: View>: View {
    let reference: TrainingCardReference
    @ViewBuilder let content: () -> Content

    private var isValid: Bool {
        do {
            try reference.validate()
            return true
        } catch {
            return false
        }
    }

    var body: some View {
        if isValid {
            VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
                content()
                DisclosureGroup("Record details") {
                    Text(reference.objectId).textSelection(.enabled)
                    Text("Revision \(reference.revision)")
                }
                .font(.footnote)
                .accessibilityIdentifier("training_card_record_\(reference.component.rawValue)")
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("Training card unavailable. Refresh training to try again.")
                .font(.footnote)
                .accessibilityIdentifier("training_invalid_card")
        }
    }
}

struct MesoPlanCard: View {
    @Environment(\.theme) private var theme
    let plan: CanvasPlan
    let reference: TrainingCardReference
    let expand: (TrainingCardAction) -> Void

    var body: some View {
        ApprovedTrainingCard(reference: reference) {
            Text("Your weekly program").font(.headline)
            Text("\(plan.sessions.count) sessions · saved plan")
            Button("Open weekly program") {
                expand(TrainingCardAction(reference: reference, name: .expand))
            }
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .accessibilityIdentifier("training_expand_plan")
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
    }
}

struct PlanChangeCard: View {
    let stored: TrainingPlanStoredProposal
    let busy: Bool
    let decide: (TrainingCardAction) -> Void

    var body: some View {
        ApprovedTrainingCard(reference: stored.cardReference) {
            Text(stored.proposal.reason).font(.headline)
            Text("Proposed by \(stored.proposal.actor.kind)")
            ForEach(stored.proposal.summary, id: \.self) { Text($0) }
            if let base = stored.proposal.baseRevision {
                Text("Based on saved revision \(base)").font(.footnote)
            }
            DisclosureGroup("Engine diff and reasons") {
                ForEach(Array((stored.proposal.proposedDiff ?? []).enumerated()), id: \.offset) { _, diff in
                    VStack(alignment: .leading) {
                        Text(diff.field).font(.subheadline.weight(.medium))
                        Text("Before: \(diff.before.displayText)")
                        Text("Proposed: \(diff.after.displayText)")
                    }
                    .font(.footnote)
                }
            }
            if busy { ProgressView("Saving decision…") }
            if stored.status == "proposed" {
                Button("Apply reviewed plan") { decide(TrainingCardAction(reference: stored.cardReference, name: .apply)) }
                    .accessibilityIdentifier("training_apply_recommended_plan")
                Button("Decline draft", role: .destructive) {
                    decide(TrainingCardAction(reference: stored.cardReference, name: .reject))
                }
                    .accessibilityIdentifier("training_reject_plan")
            } else {
                Text("Draft status: \(stored.status)")
            }
        }
        .disabled(busy)
    }
}

struct ExerciseSwapCard: View {
    let session: TrainingSession
    let exercise: TrainingExercisePrescription
    let canSwap: Bool
    let select: (TrainingCardAction) -> Void

    private var reference: TrainingCardReference {
        TrainingCardReference(component: .exerciseSwap, objectId: session.id,
                              revision: session.executionRevision ?? 0, exerciseId: exercise.id)
    }

    var body: some View {
        ApprovedTrainingCard(reference: reference) {
            Text("Alternatives for \(exercise.name)").font(.headline)
            Text("Today only. Your saved weekly plan stays in place.").font(.footnote)
            if !canSwap {
                Text("This movement has recorded or pending sets. Keep it or review the session before swapping.")
            } else if (exercise.substitutions ?? []).isEmpty {
                Text("No eligible alternative meets your current constraints. Move it later or skip it today.")
            } else {
                ForEach(exercise.substitutions ?? []) { alternative in
                    VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
                        Text(alternative.name).font(.subheadline.weight(.medium))
                        Text("\(alternative.sets) sets · \(alternative.repRange.min)–\(alternative.repRange.max) reps · \(alternative.targetRir) RIR")
                        Text("Same target muscle: \(alternative.primaryMuscle). Establish a new load for this variant.")
                        Text(alternative.loadInstruction ?? "Choose a conservative starting load.")
                        TrainingVariantSetupView(variantId: alternative.id, setup: alternative.setup)
                        Button("Use \(alternative.name)") {
                            select(TrainingCardAction(reference: reference, name: .swap, alternativeId: alternative.id))
                        }
                        .frame(minHeight: JovieTokens.minimumHitTarget)
                        .accessibilityIdentifier("training_swap_\(alternative.id)")
                    }
                }
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension TrainingPlanStoredProposal {
    var cardReference: TrainingCardReference {
        TrainingCardReference(component: .planChange, objectId: proposal.id, revision: proposal.plan.revision)
    }
}

struct TrainingVariantSetupView: View {
    let variantId: String
    let setup: TrainingVariantSetup?

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            Text("Variant: \(variantId)").textSelection(.enabled)
            if let setup {
                Text("Setup: \(setup.bodyPosition) · \(setup.torsoSupport) torso")
                Text("Equipment: \(setup.requires.joined(separator: ", "))")
                if let angle = setup.benchAngleDeg { Text("Bench: \(angle.formatted())°") }
                if let pulley = setup.pulley { Text("Pulley: \(pulley.height) · \(pulley.attachment)") }
                Text("Expected trunk demand: \(setup.trunkDemand.level) · \(setup.trunkDemand.basis)")
                Text(setup.trunkDemand.note)
                ForEach(setup.cues, id: \.self) { Text($0) }
            } else {
                Text("Setup detail unavailable. Confirm the exact variant before lifting.")
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("training_variant_setup_\(variantId)")
    }
}
