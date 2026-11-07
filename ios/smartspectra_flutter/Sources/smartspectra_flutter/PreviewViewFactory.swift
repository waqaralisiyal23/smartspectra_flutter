import Flutter
import Observation
import SmartSpectra
import UIKit

/// Creates preview views for the `smartspectra_flutter/preview` view type.
final class PreviewViewFactory: NSObject, FlutterPlatformViewFactory {
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        SmartSpectraPreviewView(frame: frame)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Shows the SDK's `imageOutput` frames. Requires `imageOutputEnabled`.
final class SmartSpectraPreviewView: NSObject, FlutterPlatformView {
    private let imageView: UIImageView

    init(frame: CGRect) {
        imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        super.init()
        Task { @MainActor [weak self] in self?.observeImage() }
    }

    func view() -> UIView { imageView }

    /// Re-arming observation loop; stops when this view is deallocated.
    @MainActor
    private func observeImage() {
        let sdk = SmartSpectraSDK.shared
        imageView.image = sdk.imageOutput
        withObservationTracking {
            _ = sdk.imageOutput
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeImage() }
        }
    }
}
