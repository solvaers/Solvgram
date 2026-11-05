import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import TelegramPresentationData
import LegacyUI

private class DocumentPickerViewController: UIDocumentPickerViewController {
    var forceDarkTheme = false
    // Keep the delegate through UIKit's result delivery. Disappearance alone is not
    // cancellation: a file provider or preview can temporarily cover this picker.
    var retainedDelegate: AnyObject?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *), self.forceDarkTheme {
            self.overrideUserInterfaceStyle = .dark
        }
    }

}

private final class LegacyICloudFileController: LegacyController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    let completion: ([URL]) -> Void
    
    init(presentation: LegacyControllerPresentation, theme: PresentationTheme?, completion: @escaping ([URL]) -> Void) {
        self.completion = completion
        
        super.init(presentation: presentation, theme: theme)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var retainedPicker: DocumentPickerViewController?
    private var didComplete = false

    private func complete(_ urls: [URL], picker: UIDocumentPickerViewController?) {
        if self.didComplete {
            return
        }
        self.didComplete = true
        let picker = (picker as? DocumentPickerViewController) ?? self.retainedPicker
        self.retainedPicker = nil
        self.completion(urls)
        picker?.delegate = nil
        picker?.retainedDelegate = nil
        picker?.presentationController?.delegate = nil
    }

    func attachPresentationDelegate(to controller: UIViewController?) {
        guard !self.didComplete else { return }
        controller?.presentationController?.delegate = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.complete([], picker: presentationController.presentedViewController as? UIDocumentPickerViewController)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.complete([], picker: controller)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.complete(urls, picker: controller)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        self.complete([url], picker: controller)
    }
}

public enum LegacyICloudFilePickerMode {
    case `default`
    case `import`
    case `export`
    
    /// iOS 14 replaced `UIDocumentPickerMode` with an `asCopy` flag on the opening/exporting
    /// initializers: the old `.open` is `asCopy: false`, while `.import` and `.exportToService`
    /// are both `asCopy: true`.
    var asCopy: Bool {
        switch self {
        case .default:
            return false
        case .import, .export:
            return true
        }
    }
}

public func legacyICloudFilePicker(theme: PresentationTheme, mode: LegacyICloudFilePickerMode = .default, hasMultiselection: Bool = false, url: URL? = nil, documentTypes: [String] = ["public.item"], forceDarkTheme: Bool = false, dismissed: @escaping () -> Void = {}, completion: @escaping ([URL]) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?
    let legacyController = LegacyICloudFileController(presentation: .modal(animateIn: true), theme: theme, completion: { urls in
        dismissImpl?()
        completion(urls)
    })
    legacyController.statusBar.statusBarStyle = .Black
    
    let controller: DocumentPickerViewController
    if case .export = mode, let url {
        controller = DocumentPickerViewController(forExporting: [url], asCopy: true)
    } else {
        // The old `documentTypes:` initializer took raw UTI strings, so identifiers the system does
        // not know (e.g. "org.xiph.flac", which the app does not declare) must not be dropped --
        // dropping them would silently make those files unselectable, and dropping all of them would
        // silently widen the picker to every file.
        let contentTypes = documentTypes.map { UTType($0) ?? UTType(importedAs: $0) }
        controller = DocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: mode.asCopy)
    }
    controller.forceDarkTheme = forceDarkTheme || theme.overallDarkAppearance
    controller.delegate = legacyController
    legacyController.retainedPicker = controller
    if #available(iOSApplicationExtension 11.0, iOS 11.0, *), hasMultiselection {
        controller.allowsMultipleSelection = true
    }
    
    legacyController.presentationCompleted = { [weak legacyController] in
        if let legacyController = legacyController {
            if let window = legacyController.view.window {
                controller.popoverPresentationController?.sourceView = window
                controller.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
                guard var presenter = window.rootViewController else { return }
                while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
                controller.retainedDelegate = legacyController
                presenter.present(controller, animated: true, completion: { [weak legacyController, weak presenter] in
                    legacyController?.attachPresentationDelegate(to: presenter?.presentedViewController)
                })
                legacyController.attachPresentationDelegate(to: controller)
                legacyController.presentationCompleted = nil
            }
        }
    }
    
    dismissImpl = { [weak legacyController] in
        if let legacyController = legacyController {
            legacyController.dismiss()
        }
        dismissed()
    }
    legacyController.bind(controller: UIViewController())
    return legacyController
}
