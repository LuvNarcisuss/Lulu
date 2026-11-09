import Foundation
import Combine
import Supabase

@MainActor
final class TravelStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isBusy = false
    @Published private(set) var profile = Record()
    @Published private(set) var lastRefreshError: String?
    @Published private(set) var realtimeError: String?
    private(set) var userID = ""
    private(set) var balance = 0
    private var snapshot = Record()
    private var generation = UUID()
    private var snapshotRequest = UUID()
    private var writeTail: Task<Void, Never>?
    private var pendingWrites = 0
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private let client: SupabaseClient

    init() {
        client = SupabaseClient(
            supabaseURL: BackendConfiguration.projectURL,
            supabaseKey: BackendConfiguration.publishableKey,
            options: .init(auth: .init(storageKey: "travel-auth-dlbaneeshycwmhgfeokx"))
        )
    }

    func rows(_ key: String) -> [Record] { snapshot.records(key) }

    func login() async throws {
        try beginWork()
        defer { isBusy = false }
        try await LaunchServices.shared.prepareForLogin()
        let session: Session
        do {
            session = try await client.auth.session
        } catch AuthError.sessionMissing {
            do { session = try await client.auth.signInAnonymously() }
            catch { LaunchServices.shared.network.markTransportFailure(error); throw error }
        } catch {
            LaunchServices.shared.network.markTransportFailure(error)
            throw error
        }
        let attempt = UUID()
        generation = attempt
        let result = try await request(path: "functions/v1/travel-entry", body: [:])
        guard case .number(let code) = result["code"], code == 0, case .object(let entryData) = result["data"], entryData.isEmpty else {
            throw StoreFailure.message("Unable to prepare your account. Please try again.")
        }
        guard generation == attempt else { throw CancellationError() }
        userID = session.user.id.uuidString.lowercased()
        try await loadSnapshot(generation: attempt)
        isAuthenticated = true
        await startRealtime()
    }

    func refresh() async throws {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        try await loadSnapshot(generation: generation)
    }

    @discardableResult
    func perform(_ action: String, _ payload: [String: JSONValue]) async throws -> Record {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        let attempt = generation
        let previous = writeTail
        pendingWrites += 1
        isBusy = true
        let operation = Task<Record, Error> { [self] in
            await previous?.value
            guard isAuthenticated, generation == attempt else { throw CancellationError() }
            let result = try await request(path: "rest/v1/rpc/travel_action", body: ["action": .string(action), "payload": .object(payload)])
            guard generation == attempt else { throw CancellationError() }
            do { try await loadSnapshot(generation: attempt) }
            catch is CancellationError { }
            catch {
                lastRefreshError = "Your change was saved. Refresh to load the latest state. \(error.localizedDescription)"
                revision += 1
            }
            return result
        }
        writeTail = Task { _ = try? await operation.value }
        defer {
            pendingWrites -= 1
            isBusy = pendingWrites > 0
        }
        return try await operation.value
    }

    func upload(data: Data, contentType: String, purpose: String) async throws -> String {
        guard isAuthenticated, !userID.isEmpty else { throw StoreFailure.authenticationRequired }
        let purposes = ["avatar", "chat", "video", "cover", "submission"]
        let extensions = ["image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "video/mp4": "mp4", "video/quicktime": "mov"]
        guard purposes.contains(purpose), let fileExtension = extensions[contentType], !data.isEmpty else {
            throw StoreFailure.message("Choose a supported photo or video.")
        }
        let limit = contentType.hasPrefix("video/") ? 50 * 1024 * 1024 : 5 * 1024 * 1024
        guard data.count <= limit else { throw StoreFailure.message("This file is too large. Videos must be under 50 MB and photos under 5 MB.") }
        let path = "\(userID)/\(purpose)/\(UUID().uuidString.lowercased()).\(fileExtension)"
        let attempt = generation
        do {
            _ = try await client.storage.from("uploads").upload(path, data: data, options: FileOptions(contentType: contentType, upsert: false))
        } catch {
            LaunchServices.shared.network.markTransportFailure(error)
            throw error
        }
        guard generation == attempt else { throw CancellationError() }
        return "uploads/\(path)"
    }

    func mediaURL(_ path: String) async throws -> URL {
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].contains(".."), !parts[1].isEmpty else {
            throw StoreFailure.message("This media reference is invalid.")
        }
        if parts[0] == "catalog" || parts[0] == "legal" {
            return try client.storage.from(parts[0]).getPublicURL(path: parts[1])
        }
        guard parts[0] == "uploads", isAuthenticated else { throw StoreFailure.authenticationRequired }
        return try await client.storage.from("uploads").createSignedURL(path: parts[1], expiresIn: 3600)
    }

    func signOut() async throws {
        try beginWork()
        defer { isBusy = false }
        try await client.auth.signOut(scope: .local)
        await clearIdentity()
    }

    func deleteAccount() async throws {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        try beginWork()
        defer { isBusy = false }
        _ = try await request(path: "functions/v1/travel-account", body: ["action": .string("delete")])
        // Deletion is already authoritative; a remote sign-out failure cannot undo it.
        try? await client.auth.signOut(scope: .local)
        await clearIdentity()
    }

    private func beginWork() throws {
        guard !isBusy else { throw StoreFailure.message("Please wait for your current request to finish.") }
        isBusy = true
    }

    private func loadSnapshot(generation attempt: UUID) async throws {
        let requestID = UUID()
        snapshotRequest = requestID
        do {
            let value = try await request(path: "rest/v1/rpc/travel_snapshot", body: [:])
            guard generation == attempt, snapshotRequest == requestID, !Task.isCancelled else { throw CancellationError() }
            let requiredKeys = ["clips", "places", "guides", "profiles", "likes", "saved_clips", "saved_places", "comments", "follows", "blocks", "reports", "journeys", "conversations", "messages", "chat_preferences", "submissions", "wallet_activity"]
            for key in requiredKeys {
                guard case .array(let items) = value[key], items.allSatisfy({ if case .object = $0 { return true }; return false }) else {
                    throw StoreFailure.message("The server returned an incomplete travel snapshot. Please retry.")
                }
            }
            guard value.record("profile").id.lowercased() == userID.lowercased(),
                  case .number(let credits) = value["balance"], credits.isFinite,
                  credits >= 0, credits.rounded(.towardZero) == credits, credits < Double(Int.max) else {
                throw StoreFailure.message("The server returned invalid account information. Please retry.")
            }
            snapshot = value
            profile = value.record("profile")
            balance = value.int("balance")
            lastRefreshError = nil
            revision += 1
        } catch {
            guard generation == attempt, snapshotRequest == requestID, !Task.isCancelled else { throw CancellationError() }
            lastRefreshError = error.localizedDescription
            revision += 1
            throw error
        }
    }

    private func request(path: String, body: [String: JSONValue]) async throws -> Record {
        let session = try await client.auth.session
        var request = URLRequest(url: BackendConfiguration.projectURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(BackendConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { LaunchServices.shared.network.markTransportFailure(error); throw error }
        guard let response = response as? HTTPURLResponse else { throw StoreFailure.message("The server response was unavailable.") }
        guard (200..<300).contains(response.statusCode) else {
            let value = try? JSONDecoder().decode(Record.self, from: data)
            throw StoreFailure.message(value?.string("message", fallback: value?.string("error", fallback: "Your request could not be completed. Please try again.") ?? "") ?? "Your request could not be completed. Please try again.")
        }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    private func startRealtime() async {
        await stopRealtime()
        let attempt = generation
        let channel = client.channel("travel-\(userID)-\(attempt.uuidString)")
        realtimeChannel = channel
        for table in ["messages", "conversation_members", "conversations"] {
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table)
            realtimeTasks.append(Task { [weak self] in
                for await _ in changes {
                    guard let self, self.generation == attempt, !Task.isCancelled else { return }
                    self.scheduleRefresh()
                }
            })
        }
        let systemEvents = channel.system()
        realtimeTasks.append(Task { [weak self] in
            for await message in systemEvents {
                guard let self, self.generation == attempt, !Task.isCancelled else { return }
                if message.payload["status"]?.stringValue == "ok" {
                    self.realtimeError = nil
                    self.scheduleRefresh()
                } else if message.payload["status"]?.stringValue == "error" {
                    self.realtimeError = "Live updates are unavailable. Refresh to check for new messages."
                }
            }
        })
        let states = channel.statusChange
        realtimeTasks.append(Task { [weak self] in
            for await state in states {
                guard let self, self.generation == attempt, !Task.isCancelled else { return }
                switch state {
                case .subscribed:
                    self.realtimeError = nil
                    self.scheduleRefresh()
                case .unsubscribed:
                    self.realtimeError = "Live updates are disconnected. Refresh to check for new messages."
                default: break
                }
            }
        })
        do { try await channel.subscribeWithError(); realtimeError = nil }
        catch { realtimeError = "Live updates are unavailable. \(error.localizedDescription)" }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled, self.isAuthenticated else { return }
            do { try await self.refresh() } catch { self.lastRefreshError = error.localizedDescription }
        }
    }

    private func stopRealtime() async {
        refreshTask?.cancel()
        refreshTask = nil
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks.removeAll()
        if let channel = realtimeChannel { await client.removeChannel(channel) }
        realtimeChannel = nil
    }

    private func clearIdentity() async {
        generation = UUID()
        await stopRealtime()
        isAuthenticated = false
        userID = ""
        profile = Record()
        snapshot = Record()
        balance = 0
        lastRefreshError = nil
        realtimeError = nil
        revision += 1
    }
}

private enum StoreFailure: LocalizedError {
    case authenticationRequired
    case message(String)
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "Sign in to continue."
        case .message(let value): return value
        }
    }
}
