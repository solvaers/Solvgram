import Foundation
import SGSimpleSettings
import UIKit
import Display
import ContextUI
import VideoMessageCameraScreen

// MARK: Solvgram — Round Video Camera "Ask Every Time": pressing the round-video button shows a
// small menu above it; recording starts, already locked (the finger has left the button by then),
// with the camera picked.

private final class SolvgramRecordButtonReferenceSource: ContextReferenceContentSource {
    private let view: UIView

    init(view: UIView) {
        self.view = view
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.view, contentAreaInScreenSpace: mainWindowScreenBounds, actionsPosition: .top)
    }
}

extension ChatControllerImpl {
    func solvgramAskRoundVideoCamera() {
        guard let micButton = self.chatDisplayNode.textInputPanelNode?.micButton else {
            self.requestVideoRecorder()
            return
        }

        // The icons take the color of the input field's sticker and keyboard buttons.
        let iconColor = self.presentationData.theme.chat.inputPanel.inputControlColor
        let items: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: SolvgramSettings.isRussian ? "Фронтальная камера" : "Front Camera", icon: { _ in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Solvgram/RoundVideoFrontCamera"), color: iconColor)
            }, action: { [weak self] _, f in
                f(.default)
                self?.solvgramStartRoundVideo(front: true)
            })),
            .action(ContextMenuActionItem(text: SolvgramSettings.isRussian ? "Задняя камера" : "Back Camera", icon: { _ in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Solvgram/RoundVideoBackCamera"), color: iconColor)
            }, action: { [weak self] _, f in
                f(.default)
                self?.solvgramStartRoundVideo(front: false)
            }))
        ]

        let controller = makeContextController(presentationData: self.presentationData, source: .reference(SolvgramRecordButtonReferenceSource(view: micButton)), items: .single(ContextController.Items(content: .list(items), prefersCompactWidth: true)), recognizer: nil, gesture: nil, disableScreenshots: false)
        self.window?.presentInGlobalOverlay(controller)
    }

    private func solvgramStartRoundVideo(front: Bool) {
        // The press that opened the menu has ended: record hands-free, as after sliding up to lock.
        self.lockMediaRecordingRequestId = self.beginMediaRecordingRequestId
        self.requestVideoRecorder(solvgramCameraIsFront: front)
    }
}
