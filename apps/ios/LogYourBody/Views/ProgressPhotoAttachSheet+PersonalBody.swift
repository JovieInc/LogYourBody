import SwiftUI

struct PersonalBodyOutlineAttachment: Equatable {
    var sessionId = UUID().uuidString
    var metricId: String?
    var accountId: String?
}

extension ProgressPhotoAttachSheet {
    func markAttached(metricsId: String, accountId: String) {
        outlineAttachment.metricId = metricsId
        outlineAttachment.accountId = accountId
        attachStatus = .success
        HapticManager.shared.successAction()
    }

    @ViewBuilder
    var personalBodyOffer: some View {
        if isSuccess, PersonalBodyPolicy.isEnabled(), !PersonalBodyEstimate.benefitCopy.isEmpty {
            let storedFrame = UserDefaults.standard.object(forKey: WireframeAvatarStorage.frame) as? Double
            PersonalBodyCaptureOffer(
                image: selectedImage,
                accountId: outlineAttachment.accountId,
                photoId: outlineAttachment.metricId,
                sessionId: outlineAttachment.sessionId,
                effectiveDate: targetDate,
                frame: storedFrame ?? 0.5
            )
        }
    }
}
