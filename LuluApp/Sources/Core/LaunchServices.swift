import UIKit
import Foundation
import UserNotifications
import Security
import Alamofire

@MainActor final class LaunchServices {
    static let shared = LaunchServices()
    let network = AppNetworkGate(origin: BackendConfiguration.projectURL)
    private(set) var deviceID = ""
    private(set) var pushToken = ""
    private(set) var pushState = "Not registered"
    private var started = false
    private var notificationRequest: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private let pushEnabled = Bundle.main.object(forInfoDictionaryKey: "PushRegistrationEnabled") as? Bool == true

    func start() {
        guard !started else { return }; started = true
        network.start()
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareNotifications() }
        }
        if UIApplication.shared.applicationState == .active { prepareNotifications() }
    }
    func prepareForLogin() async throws {
        start()
        deviceID = try InstallationIdentity.readOrCreate()
        try await network.waitUntilReady()
        try Task.checkCancellation()
    }
    private func prepareNotifications() {
        guard pushEnabled, UIApplication.shared.applicationState == .active, notificationRequest == nil else {
            if !pushEnabled { pushState = "Signing configuration required" }
            return
        }
        notificationRequest = Task { [weak self] in
            guard let self else { return }; defer { self.notificationRequest = nil }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
                catch { self.pushState = "Notification permission unavailable" }
            }
            guard UIApplication.shared.applicationState == .active else { return }
            self.pushState = "Registering"
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    func registered(_ token: Data) {
        pushToken = token.map { String(format: "%02x", $0) }.joined()
        pushState = pushToken.isEmpty ? "No token returned" : "Registered"
    }
    func registrationFailed() { pushToken = ""; pushState = "Registration unavailable" }
    deinit { if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }; notificationRequest?.cancel() }
}

private enum InstallationIdentity {
    static func readOrCreate() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "travel.dlbaneeshycwmhgfeokx.installation", kSecAttrAccount as String: "device-uuid"]
        func read() throws -> String? {
            var request = query
            request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &value)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = value as? Data, let string = String(data: data, encoding: .utf8), UUID(uuidString: string) != nil else { throw StartupFailure.secureStorage }
            return string
        }
        if let existing = try read() { return existing }
        let id = UUID().uuidString.lowercased()
        var attributes = query
        attributes[kSecValueData as String] = Data(id.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem, let saved = try read() else { throw StartupFailure.secureStorage }
        return saved
    }
}

private final class ProbeRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class AppNetworkGate {
    private struct Waiter {
        let continuation: CheckedContinuation<Void, Error>
        var remaining: TimeInterval = 30
        var activeSince: ContinuousClock.Instant?
    }
    private let origin: URL
    private let reachability = NetworkReachabilityManager()
    private let redirects = ProbeRedirectDelegate()
    private let clock = ContinuousClock()
    private var started = false
    private var ready = false
    private var explicitlyOffline = false
    private var generation = UUID()
    private var probe: Task<Void, Never>?
    private var retry: DispatchWorkItem?
    private var deadline: DispatchWorkItem?
    private var retryIndex = 0
    private var waiters: [UUID: Waiter] = [:]
    private var observers: [NSObjectProtocol] = []
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
    }()
    init(origin: URL) { self.origin = origin }
    func start() {
        guard !started else { return }; started = true
        _ = reachability?.startListening(onQueue: .main) { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.explicitlyOffline = status == .notReachable
                self.invalidate()
                self.startProbe()
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pauseBudgets() } })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.retry?.cancel(); self?.retry = nil; self?.invalidate() } })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.resumeBudgets(); self?.startProbe() } })
        Task { [weak self] in self?.startProbe() }
    }
    func waitUntilReady() async throws {
        start()
        if ready { return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                waiters[id] = Waiter(continuation: continuation, activeSince: UIApplication.shared.applicationState == .active ? clock.now : nil)
                scheduleDeadline(); startProbe()
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancelWaiter(id) } })
    }
    func markTransportFailure(_ error: Error) {
        var current = error as NSError
        for _ in 0..<4 {
            if current.domain == NSURLErrorDomain {
                guard current.code != URLError.cancelled.rawValue else { return }
                invalidate(); startProbe(); return
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return }
            current = underlying
        }
    }
    private func invalidate() {
        ready = false; generation = UUID()
        probe?.cancel(); probe = nil
        retry?.cancel(); retry = nil; retryIndex = 0
    }
    private func startProbe() {
        guard !ready, probe == nil, !explicitlyOffline, UIApplication.shared.applicationState != .background else { return }
        retry?.cancel(); retry = nil
        let identity = generation
        var request = URLRequest(url: origin)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        probe = Task { [weak self] in
            guard let self else { return }
            do {
                let (_, response) = try await self.session.data(for: request)
                guard !Task.isCancelled, self.generation == identity else { return }
                self.probe = nil
                guard response is HTTPURLResponse else { self.scheduleRetry(); return }
                self.ready = true; self.retryIndex = 0
                let pending = self.waiters; self.waiters.removeAll(); self.deadline?.cancel(); self.deadline = nil
                for waiter in pending.values { waiter.continuation.resume() }
            } catch {
                guard !Task.isCancelled, self.generation == identity else { return }
                self.probe = nil; self.ready = false; self.scheduleRetry()
            }
        }
    }
    private func scheduleRetry() {
        guard UIApplication.shared.applicationState == .active, retry == nil else { return }
        let delays: [Double] = [2, 4, 8, 16, 30]
        let delay = delays[min(retryIndex, delays.count - 1)]; retryIndex += 1
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.retry = nil; self?.startProbe() } }
        retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: clock.now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1_000_000_000_000_000_000
    }
    private func pauseBudgets() {
        deadline?.cancel(); deadline = nil
        for id in Array(waiters.keys) {
            guard var waiter = waiters[id], let start = waiter.activeSince else { continue }
            waiter.remaining = max(0, waiter.remaining - elapsed(since: start)); waiter.activeSince = nil; waiters[id] = waiter
        }
    }
    private func resumeBudgets() {
        for id in Array(waiters.keys) { guard var waiter = waiters[id], waiter.activeSince == nil else { continue }; waiter.activeSince = clock.now; waiters[id] = waiter }
        scheduleDeadline()
    }
    private func scheduleDeadline() {
        deadline?.cancel(); deadline = nil
        guard UIApplication.shared.applicationState == .active else { return }
        let durations = waiters.values.compactMap { waiter -> Double? in guard let start = waiter.activeSince else { return nil }; return max(0, waiter.remaining - elapsed(since: start)) }
        guard let next = durations.min() else { return }
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.expireWaiters() } }
        deadline = work; DispatchQueue.main.asyncAfter(deadline: .now() + next, execute: work)
    }
    private func expireWaiters() {
        guard UIApplication.shared.applicationState == .active else { pauseBudgets(); return }
        let expired = waiters.filter { _, waiter in guard let start = waiter.activeSince else { return false }; return waiter.remaining - elapsed(since: start) <= 0.01 }.map(\.key)
        for id in expired { waiters.removeValue(forKey: id)?.continuation.resume(throwing: StartupFailure.network) }
        scheduleDeadline()
    }
    private func cancelWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError()); scheduleDeadline() }
    deinit {
        reachability?.stopListening(); probe?.cancel(); retry?.cancel(); deadline?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for waiter in waiters.values { waiter.continuation.resume(throwing: CancellationError()) }
    }
}

private enum StartupFailure: LocalizedError {
    case secureStorage, network
    var errorDescription: String? {
        switch self {
        case .secureStorage: return "Secure device storage is unavailable. Please try again."
        case .network: return "A connection could not be established. Check internet access and try again."
        }
    }
}
