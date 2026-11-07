import AVFoundation
import Flutter
import Observation
import SmartSpectra
import UIKit

/// Flutter bridge to the SmartSpectra Swift SDK.
public final class SmartspectraFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    /// Bumped on every listen/cancel so stale observation loops stop.
    private var generation = 0
    private let mapper = MetricsMapper()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SmartspectraFlutterPlugin()
        let methods = FlutterMethodChannel(
            name: "smartspectra_flutter/methods",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methods)
        let events = FlutterEventChannel(
            name: "smartspectra_flutter/events",
            binaryMessenger: registrar.messenger()
        )
        events.setStreamHandler(instance)
        registrar.register(PreviewViewFactory(), withId: "smartspectra_flutter/preview")
        instance.stopWhenBackgrounded()
    }

    /// Stops measuring as soon as the app leaves the screen, so the camera
    /// never keeps running in the background. The app calls start() again
    /// when the user returns. Works with both app- and scene-based lifecycles.
    private func stopWhenBackgrounded() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                UIApplication.shared.isIdleTimerDisabled = false
                try? await SmartSpectraSDK.shared.stop()
            }
        }
    }

    // MARK: - Methods

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task { @MainActor in
            switch call.method {
            case "configure":
                self.configure(call.arguments as? [String: Any] ?? [:], result: result)
            case "hasCameraPermission":
                result(AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
            case "requestCameraPermission":
                self.requestCameraPermission(result)
            case "start":
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                    result(FlutterError(
                        code: "inputUnavailable",
                        message: "Camera permission has not been granted",
                        details: nil
                    ))
                    return
                }
                self.mapper.reset()
                await self.run(result) { try await SmartSpectraSDK.shared.start() }
            case "stop":
                await self.run(result) { try await SmartSpectraSDK.shared.stop() }
            case "reset":
                await self.run(result) { try await SmartSpectraSDK.shared.reset() }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    @MainActor
    private func configure(_ args: [String: Any], result: FlutterResult) {
        guard let apiKey = args["apiKey"] as? String, !apiKey.isEmpty else {
            result(FlutterError(code: "configurationFailed", message: "apiKey is required", details: nil))
            return
        }
        let sdk = SmartSpectraSDK.shared
        sdk.config.apiKey = apiKey
        sdk.config.enableTelemetry = args["enableTelemetry"] as? Bool ?? false
        sdk.config.imageOutputEnabled = args["previewEnabled"] as? Bool ?? true
        sdk.config.requestedMetrics = Self.requestedMetrics(args["metrics"] as? [String])

        let camera: CameraSelection
        switch args["camera"] as? String {
        case "back": camera = .back
        case "defaultCamera": camera = .default
        default: camera = .front
        }
        do {
            try sdk.useCamera(camera)
            result(nil)
        } catch {
            result(Self.flutterError(error))
        }
    }

    private static func requestedMetrics(_ names: [String]?) -> [MetricType]? {
        guard let names, !names.isEmpty else { return nil }
        var out: [MetricType] = []
        func add(_ metrics: [MetricType]) {
            for metric in metrics where !out.contains(metric) { out.append(metric) }
        }
        for name in names {
            switch name {
            case "breathing": add(SmartSpectraConfig.breathingMetrics)
            case "cardio": add(SmartSpectraConfig.cardioMetrics)
            case "expressions": add([.expressions])
            case "blinking": add([.blinking])
            case "talking": add([.talking])
            case "eda": add(SmartSpectraConfig.edaMetrics)
            default: break
            }
        }
        return out.isEmpty ? nil : out
    }

    @MainActor
    private func requestCameraPermission(_ result: @escaping FlutterResult) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            result(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { result(granted) }
            }
        default:
            // Denied or restricted: the user must change it in Settings.
            result(false)
        }
    }

    @MainActor
    private func run(_ result: FlutterResult, _ body: () async throws -> Void) async {
        do {
            try await body()
            result(nil)
        } catch {
            result(Self.flutterError(error))
        }
    }

    private static func flutterError(_ error: Error) -> FlutterError {
        if let error = error as? SmartSpectraError {
            return FlutterError(
                code: "\(error.code)",
                message: error.message,
                details: ["retryable": error.retryable]
            )
        }
        return FlutterError(code: "processingFailed", message: error.localizedDescription, details: nil)
    }

    // MARK: - Events

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        generation += 1
        let current = generation
        Task { @MainActor in self.startObserving(current) }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        generation += 1
        return nil
    }

    @MainActor
    private func startObserving(_ gen: Int) {
        observe(\.processingStatus, gen) { [weak self] status in
            let name = "\(status)".lowercased()
            // Keep the screen awake only while a measurement is starting or running.
            UIApplication.shared.isIdleTimerDisabled = name == "starting" || name == "running"
            self?.emit("status", "\(status)")
        }
        observe(\.validationStatus, gen) { [weak self] status in
            guard let status else { return }
            self?.emit("validation", ["code": "\(status.code)", "hint": status.hint])
        }
        observe(\.error, gen) { [weak self] error in
            guard let error else { return }
            self?.emit("error", [
                "code": "\(error.code)",
                "message": error.message,
                "retryable": error.retryable,
            ])
        }
        observe(\.metrics, gen) { [weak self] metrics in
            guard let self, let metrics, let mapped = self.mapper.map(metrics) else { return }
            self.emit("metrics", mapped)
        }
    }

    /// Observes one `@Observable` SDK property, re-arming after each change,
    /// until the stream is cancelled (generation changes).
    @MainActor
    private func observe<T>(
        _ keyPath: KeyPath<SmartSpectraSDK, T>,
        _ gen: Int,
        _ handler: @escaping @MainActor (T) -> Void
    ) {
        guard gen == generation else { return }
        let sdk = SmartSpectraSDK.shared
        handler(sdk[keyPath: keyPath])
        withObservationTracking {
            _ = sdk[keyPath: keyPath]
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observe(keyPath, gen, handler)
            }
        }
    }

    private func emit(_ type: String, _ data: Any?) {
        eventSink?(["type": type, "data": data as Any])
    }
}
