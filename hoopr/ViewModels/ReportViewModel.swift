import Combine
import Foundation

/// Backs `ReportSheet` — a player or a squad being flagged for review (App
/// Review Guideline 1.2). Built per presentation, like `CreateGameViewModel`.
///
/// One view model for both targets because the two flows are the same flow:
/// pick a reason, optionally say more, send. Only the noun changes.
@MainActor
final class ReportViewModel: ObservableObject, Identifiable {
    /// `nil` until one is picked; nothing is preselected, so a report always
    /// carries a reason somebody chose.
    @Published var reason: Report.Reason?
    @Published var details = ""

    @Published private(set) var isSubmitting = false
    @Published private(set) var didSubmit = false
    @Published private(set) var errorMessage: String?

    let targetType: Report.TargetType
    let targetId: String

    /// As it reads in a sentence — "Report Rim Reapers".
    let targetName: String

    private let safetyService: SafetyService

    init(
        targetType: Report.TargetType,
        targetId: String,
        targetName: String,
        safetyService: SafetyService
    ) {
        self.targetType = targetType
        self.targetId = targetId
        self.targetName = targetName
        self.safetyService = safetyService
    }

    var canSubmit: Bool {
        Self.canSubmit(reason: reason, details: details, isSubmitting: isSubmitting)
    }

    nonisolated static func canSubmit(reason: Report.Reason?, details: String, isSubmitting: Bool) -> Bool {
        reason != nil && !isSubmitting && detailsHint(for: details) == nil
    }

    /// Why the note can't be sent, shown under the field before the write
    /// rather than coming back as a server refusal.
    var detailsHint: String? { Self.detailsHint(for: details) }

    nonisolated static func detailsHint(for details: String) -> String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.count > Report.maxDetailsLength else { return nil }
        return SafetyService.message(for: .detailsTooLong, whileDoing: "sending that report")
    }

    /// The reasons on offer. "Pretending to be someone else" is about a
    /// person, so a squad isn't offered it.
    var reasons: [Report.Reason] { Self.reasons(for: targetType) }

    nonisolated static func reasons(for targetType: Report.TargetType) -> [Report.Reason] {
        switch targetType {
        case .player: Report.Reason.allCases
        case .squad:  Report.Reason.allCases.filter { $0 != .impersonation }
        }
    }

    func submit() async {
        guard canSubmit, let reason else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let report = Report(
            targetType: targetType,
            targetId: targetId,
            reason: reason,
            details: details
        )

        do {
            try await safetyService.submit(report)
            didSubmit = true
        } catch let error as SafetyError {
            errorMessage = SafetyService.message(for: error, whileDoing: "sending that report")
        } catch {
            errorMessage = SafetyService.message(for: .unknown(""), whileDoing: "sending that report")
        }
    }
}
