import AVFoundation
import CoreImage
import UIKit

struct TravelFriendCode {
    static func memberID(from raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = canonicalUUID(value) { return id }
        guard let components = URLComponents(string: value),
              components.scheme == "travelapp", components.host == "friend",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.path.hasPrefix("/"),
              components.path.dropFirst().contains("/") == false else { return nil }
        return canonicalUUID(String(components.path.dropFirst()))
    }
    static func value(for id: String) -> String? {
        canonicalUUID(id).map { "travelapp://friend/\($0)" }
    }
    private static func canonicalUUID(_ value: String) -> String? {
        guard value.count == 36, let id = UUID(uuidString: value), id.uuidString.caseInsensitiveCompare(value) == .orderedSame else { return nil }
        return id.uuidString.lowercased()
    }
}

@MainActor
final class TravelerCodeController: TravelScreen {
    override func render() {
        super.render(); title = "My traveler code"
        appendTravelerCode()
    }
}

@MainActor
extension TravelScreen {
    func appendTravelerCode() {
        guard let value = TravelFriendCode.value(for: store.userID), let image = Self.codeImage(value) else {
            updateProblem("Your traveler code could not be generated. Please refresh your account.", for: "travelerCode"); return
        }
        updateProblem(nil, for: "travelerCode")
        content.addArrangedSubview(text(store.profile.string("display_name", fallback: "Your traveler code"), 30, display: true))
        content.addArrangedSubview(text("Share this code so another traveler can find your member profile. It contains your traveler ID, not your sign-in details.", color: Palette.muted))
        let code = UIImageView(image: image)
        code.contentMode = .scaleAspectFit
        code.layer.magnificationFilter = .nearest
        code.heightAnchor.constraint(equalToConstant: 260).isActive = true
        code.backgroundColor = .white
        code.isAccessibilityElement = true; code.accessibilityLabel = "Your traveler QR code"
        content.addArrangedSubview(card([code], color: .white))
        content.addArrangedSubview(text(store.userID, 13, color: Palette.muted))
        content.addArrangedSubview(action("Share traveler code", icon: "icon-share") { [weak self] in self?.share([image, value]) })
        content.addArrangedSubview(action("Copy traveler ID", icon: "icon-profile", filled: false) { [weak self] in
            guard let self else { return }; UIPasteboard.general.string = self.store.userID; self.notice("Traveler ID copied.")
        })
    }
    private static func codeImage(_ value: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        let quietZone = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor.white).cropped(to: quietZone)
        let output = code.composited(over: white).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

@MainActor
final class FriendScannerController: TravelScreen {
    private let capture = FriendCaptureSession()
    private let cameraView = CameraPreviewView()
    private let cameraStatus = text("Point your camera at a traveler QR code.", 15, color: Palette.muted)
    private let manualID = input("Or enter a full traveler ID")
    private var built = false
    private var visible = false
    private var resolving = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var captureObservers: [NSObjectProtocol] = []

    override func render() {
        guard !built else { return }
        super.render(); built = true; title = "Scan traveler code"
        cameraView.preview.session = capture.session
        cameraView.preview.videoGravity = .resizeAspectFill
        cameraView.backgroundColor = Palette.ink
        cameraView.layer.cornerRadius = 24; cameraView.clipsToBounds = true
        cameraView.heightAnchor.constraint(equalToConstant: 330).isActive = true
        cameraView.accessibilityLabel = "Camera preview for traveler QR codes"
        content.addArrangedSubview(cameraView)
        content.addArrangedSubview(cameraStatus)
        content.addArrangedSubview(action("Scan again", icon: "icon-camera", filled: false) { [weak self] in self?.startCamera() })
        content.addArrangedSubview(text("Only traveler codes and full member IDs are accepted. Web links are never opened by this scanner.", 14, color: Palette.muted))
        content.addArrangedSubview(manualID)
        manualID.autocapitalizationType = .none; manualID.autocorrectionType = .no
        content.addArrangedSubview(action("Find this traveler", icon: "icon-search") { [weak self] in
            guard let self else { return }; self.resolve(self.manualID.text ?? "")
        })
        content.addArrangedSubview(action("Camera settings", icon: "icon-settings", filled: false) {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        capture.onCode = { [weak self] value in self?.resolve(value) }
        capture.onFailure = { [weak self] value in self?.showScannerError(value) }
        for notification in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            captureObservers.append(NotificationCenter.default.addObserver(forName: notification, object: capture.session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.visible else { return }
                    self.capture.stop()
                    self.showScannerError("The camera was interrupted. Choose Scan again or enter a full traveler ID.")
                }
            })
        }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.capture.stop() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, self.visible, !self.resolving else { return }; self.startCamera() }
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let connection = cameraView.preview.connection, connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); visible = true; startCamera() }
    override func viewWillDisappear(_ animated: Bool) { visible = false; capture.stop(); super.viewWillDisappear(animated) }
    private func showScannerError(_ message: String) {
        cameraStatus.text = nil
        notice(message)
    }

    private func startCamera() {
        guard visible, !resolving, UIApplication.shared.applicationState == .active else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraStatus.text = "Point your camera at a traveler QR code."; capture.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.visible, UIApplication.shared.applicationState == .active else { return }
                    if granted { self.startCamera() }
                    else { self.showScannerError("Camera access was not allowed. Enter a full traveler ID or enable access in Settings.") }
                }
            }
        case .denied, .restricted: showScannerError("Camera access is unavailable. Enter a full traveler ID or check Settings.")
        @unknown default: showScannerError("Camera access is unavailable on this device.")
        }
    }
    private func resolve(_ raw: String) {
        guard !resolving, visible else { return }
        capture.stop()
        guard let id = TravelFriendCode.memberID(from: raw) else {
            showScannerError("This is not a traveler code or a full traveler ID. Choose Scan again to continue."); return
        }
        guard id.caseInsensitiveCompare(store.userID) != .orderedSame else {
            showScannerError("This is your own traveler code. Share it with another traveler."); return
        }
        resolving = true
        let owner = store.userID
        cameraStatus.text = "Finding traveler…"
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.refresh()
                guard self.visible, owner == self.store.userID else { self.resolving = false; return }
                guard let profile = self.store.rows("profiles").first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame && !$0.bool("is_editorial") }) else {
                    self.showScannerError("This traveler is unavailable or is not discoverable. Choose Scan again to continue."); self.resolving = false; return
                }
                guard !isBlocked(profile.id, store: self.store) else {
                    self.showScannerError("This traveler cannot be opened while blocked."); self.resolving = false; return
                }
                self.resolving = false
                self.push(PublicProfileController(store: self.store, profileID: profile.id))
            } catch is CancellationError {
                self.resolving = false
                self.cameraStatus.text = nil
            } catch {
                self.resolving = false
                self.showScannerError("Traveler lookup failed: \(error.localizedDescription)")
            }
        }
    }
    deinit {
        capture.stop()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        captureObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// All capture configuration and start/stop work runs off the main thread on one serial queue.
private final class FriendCaptureSession: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var onCode: (@MainActor (String) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?
    private let queue = DispatchQueue(label: "travel.friend.capture")
    private let lock = NSLock()
    private var requested = false
    private var configured = false
    private var isRequested: Bool { lock.lock(); defer { lock.unlock() }; return requested }
    func start() {
        lock.lock(); requested = true; lock.unlock()
        queue.async { [weak self] in
            guard let self, self.isRequested else { return }
            do {
                if !self.configured { try self.configure() }
                guard self.isRequested else { return }
                if !self.session.isRunning { self.session.startRunning() }
            } catch {
                self.stop()
                Task { @MainActor [weak self] in self?.onFailure?("A camera is unavailable. You can enter a full traveler ID instead.") }
            }
        }
    }
    func stop() {
        lock.lock(); requested = false; lock.unlock()
        let activeSession = session
        queue.async {
            if activeSession.isRunning { activeSession.stopRunning() }
        }
    }
    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video) else { throw PhotoImportError.unreadable }
        let input = try AVCaptureDeviceInput(device: device)
        let metadata = AVCaptureMetadataOutput()
        session.beginConfiguration()
        var succeeded = false
        defer {
            if !succeeded {
                if session.inputs.contains(where: { $0 === input }) { session.removeInput(input) }
                if session.outputs.contains(where: { $0 === metadata }) { session.removeOutput(metadata) }
            }
            session.commitConfiguration()
        }
        guard session.canAddInput(input), session.canAddOutput(metadata) else { throw PhotoImportError.unreadable }
        session.addInput(input); session.addOutput(metadata)
        guard metadata.availableMetadataObjectTypes.contains(.qr) else { throw PhotoImportError.unreadable }
        metadata.setMetadataObjectsDelegate(self, queue: .main)
        metadata.metadataObjectTypes = [.qr]
        configured = true; succeeded = true
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isRequested, let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        stop()
        Task { @MainActor [weak self] in self?.onCode?(value) }
    }
}
