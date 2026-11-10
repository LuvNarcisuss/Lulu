import AVFoundation
import UIKit

@MainActor
final class LocalVideoPreviewController: TravelScreen {
    private let capture = FrontCameraPreviewSession()
    private let cameraView = CameraPreviewView()
    private let status = text("Preparing camera…", 16, color: Palette.muted)
    private var visible = false
    private var requestingAccess = false
    private var observers: [NSObjectProtocol] = []

    private lazy var settingsButton = action("Open Settings", icon: "icon-settings", filled: false) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    private lazy var retryButton = action("Try again", icon: "icon-refresh", filled: false) { [weak self] in
        self?.startCameraIfVisible()
    }

    override func viewDidLoad() {
        automaticRefresh = false
        showsReadFailureOverlay = false
        super.viewDidLoad()
        title = "Camera preview"

        cameraView.preview.session = capture.session
        cameraView.preview.videoGravity = .resizeAspectFill
        cameraView.backgroundColor = Palette.ink
        cameraView.layer.cornerRadius = 24
        cameraView.clipsToBounds = true
        cameraView.heightAnchor.constraint(equalToConstant: 330).isActive = true
        cameraView.isAccessibilityElement = true
        cameraView.accessibilityLabel = "Front camera preview"

        content.addArrangedSubview(cameraView)
        content.addArrangedSubview(status)
        content.addArrangedSubview(settingsButton)
        content.addArrangedSubview(retryButton)
        show("Preparing camera…")

        observe(UIApplication.willResignActiveNotification) {
            $0.capture.stop()
            $0.cameraView.isHidden = true
        }
        observe(UIApplication.didBecomeActiveNotification) { $0.startCameraIfVisible() }
        observe(AVCaptureSession.wasInterruptedNotification, object: capture.session) {
            $0.cameraStopped("Camera preview was interrupted.")
        }
        observe(AVCaptureSession.interruptionEndedNotification, object: capture.session) {
            $0.startCameraIfVisible()
        }
        observe(AVCaptureSession.runtimeErrorNotification, object: capture.session) {
            $0.cameraStopped("Camera preview is unavailable.")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        startCameraIfVisible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        capture.stop()
        super.viewWillDisappear(animated)
    }

    private func startCameraIfVisible() {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            show("Preparing camera…")
            capture.start { [weak self] running in
                guard let self, self.visible, UIApplication.shared.applicationState == .active else { return }
                guard running else {
                    self.show("Front camera is unavailable.", retry: true)
                    return
                }
                if let connection = self.cameraView.preview.connection {
                    if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }
                self.show("Local camera preview", preview: true)
            }
        case .notDetermined:
            show("Allow camera access to see your preview.")
            guard !requestingAccess else { return }
            requestingAccess = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.requestingAccess = false
                    guard self.visible else { return }
                    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                        self.show("Front camera is unavailable.", retry: true)
                    } else {
                        self.startCameraIfVisible()
                    }
                }
            }
        case .denied:
            show("Camera access is off.", settings: true)
        case .restricted:
            show("Camera access is restricted on this device.")
        @unknown default:
            show("Camera access is unavailable.")
        }
    }

    private func show(_ message: String, preview: Bool = false, settings: Bool = false, retry: Bool = false) {
        status.text = message
        cameraView.isHidden = !preview
        settingsButton.isHidden = !settings
        retryButton.isHidden = !retry
    }

    private func cameraStopped(_ message: String) {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        capture.stop()
        show(message, retry: true)
    }

    private func observe(_ name: Notification.Name, object: AnyObject? = nil,
                         _ handler: @escaping @MainActor (LocalVideoPreviewController) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let self { handler(self) }
            }
        })
    }

    deinit {
        capture.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

/// Session configuration and capture run on the serial queue. The lock guards the current request.
private final class FrontCameraPreviewSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "travel.chat.camera-preview")
    private let lock = NSLock()
    private var request: UUID?

    func start(completion: @escaping @MainActor (Bool) -> Void) {
        let id = UUID()
        setRequest(id)
        queue.async { [self] in
            guard isCurrent(id) else { return }
            if configureIfNeeded(), isCurrent(id), !session.isRunning { session.startRunning() }
            let running = session.isRunning
            Task { @MainActor [self] in
                if self.isCurrent(id) { completion(running) }
            }
        }
    }

    func stop() {
        setRequest(nil)
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() -> Bool {
        if !session.inputs.isEmpty { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }

    private func setRequest(_ value: UUID?) {
        lock.lock()
        request = value
        lock.unlock()
    }

    private func isCurrent(_ value: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return request == value
    }
}
