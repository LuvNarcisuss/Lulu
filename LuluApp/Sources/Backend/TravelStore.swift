import Foundation
import Combine
import Security
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
    private(set) var hasCoinState = false
    private(set) var coinActivity: [Record] = []
    private(set) var guideOffers: [Record] = []
    private(set) var sandboxGuides: [Record] = []
    private(set) lazy var payments = PaymentCatalogAdapter(store: self)
    private var coinStateRequest = UUID()
    private(set) var hiddenPlaceIDs: Set<String> = []
    private(set) var hasGuideVisibility = false
    private static let guideVisibilityPath = "rest/v1/rpc/travel_guide_visibility"
    private var guideVisibilityVersion = UUID()
    private var workLikeCounts: [String: [String: Int]] = [:]
    private var snapshot = Record()
    private var generation = UUID()
    private var snapshotRequest = UUID()
    private var writeTail: Task<Void, Never>?
    private var isDeletingAccount = false
    private var pendingWrites = 0
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private let client: SupabaseClient
    private let companyStorage = GuestCredentialStorage(service: "lulu.company.auth")
    private let previousStorage = GuestCredentialStorage(service: "supabase.gotrue.swift")
    private static let guestSessionKey = "travel-auth-ziryoihosvlqnbvfdvbw"
    private static let pendingAccountKey = "pending-legacy-account"
    private lazy var guestClient = SupabaseClient(
        supabaseURL: BackendConfiguration.projectURL,
        supabaseKey: BackendConfiguration.publishableKey,
        options: .init(auth: .init(storage: companyStorage, storageKey: TravelStore.guestSessionKey,
                                   autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
    )
    private lazy var previousClient = SupabaseClient(
        supabaseURL: BackendConfiguration.legacyProjectURL,
        supabaseKey: BackendConfiguration.legacyPublishableKey,
        options: .init(auth: .init(storage: previousStorage, storageKey: BackendConfiguration.legacySessionKey,
                                   autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
    )

    init() {
        client = SupabaseClient(
            supabaseURL: BackendConfiguration.projectURL,
            supabaseKey: BackendConfiguration.publishableKey,
            options: .init(auth: .init(storage: EmailSessionStorage()))
        )
    }

    func rows(_ key: String) -> [Record] { snapshot.records(key) }

    func contentLikeCount(kind: String, id: String) -> Int? {
        workLikeCounts[kind]?[id]
    }

    private func indexWorkLikes(_ statistics: Record?) -> [String: [String: Int]] {
        var counts: [String: [String: Int]] = [:]
        for kind in ["clips", "guides"] {
            for item in statistics?.records(kind) ?? [] {
                guard !item.id.isEmpty, case .number(let value) = item["likes"],
                      value.isFinite, value >= 0, value < Double(Int.max), value.rounded() == value else { continue }
                counts[kind, default: [:]][item.id] = Int(value)
            }
        }
        return counts
    }

    var visiblePlaces: [Record] {
        rows("places").filter { !hiddenPlaceIDs.contains($0.id) }
    }

    var hasGuestToUpgrade: Bool {
        guestClient.auth.currentUser?.isAnonymous == true || previousClient.auth.currentSession != nil
    }

    func register(email: String, password: String) async throws {
        guard !isAuthenticated else { throw StoreFailure.message("Sign out before creating another account.") }
        try beginWork()
        defer { isBusy = false }
        try await LaunchServices.shared.prepareForLogin()
        let previousID = try pendingAccountID()
        let hasGuest = try companyStorage.retrieve(key: Self.guestSessionKey) != nil
        if hasGuest || previousID != nil {
            // The ticket must bind while the destination is still a guest.
            let session: Session
            if hasGuest {
                session = try await guestClient.auth.session
            } else {
                let original = try await previousClient.auth.session
                guard original.user.id == previousID else { throw GuestTransferError() }
                session = try await guestClient.auth.signInAnonymously()
            }
            guard guestClient.auth.currentUser?.id == session.user.id else { throw GuestTransferError() }
            let owner = try await guestClient.auth.user()
            guard owner.id == session.user.id else { throw GuestTransferError() }
            guard owner.isAnonymous else {
                throw StoreFailure.message("Your saved account already has an email address. Sign in to continue.")
            }
            let parameters = try await transferParameters(previousID: previousID, destination: owner.id)
            let accountID = try await enter(using: guestClient, parameters: parameters)
            if let previousID, previousID != accountID { throw GuestTransferError() }
            let updated = try await guestClient.auth.update(user: UserAttributes(email: email, password: password))
            guard updated.id == owner.id, !updated.isAnonymous, updated.email == email,
                  updated.emailConfirmedAt != nil else { throw GuestTransferError() }
        } else {
            let response = try await client.auth.signUp(email: email, password: password)
            guard let session = response.session, !session.user.isAnonymous, session.user.email == email,
                  session.user.emailConfirmedAt != nil else {
                throw StoreFailure.message("Registration could not be confirmed. Please try signing in.")
            }
            // The SDK clears its local session before contacting the sign-out endpoint.
            try? await client.auth.signOut(scope: .local)
        }
    }

    private func enter(using source: SupabaseClient, parameters: [String: JSONValue] = [:]) async throws -> UUID {
        let result = try await request(path: "functions/v1/travel-entry", body: parameters, using: source)
        guard case .number(let code) = result["code"], code == 0, case .object(let entryData) = result["data"],
              entryData.isEmpty, let accountID = UUID(uuidString: result.string("account_id")) else {
            throw StoreFailure.message("Unable to prepare your account. Please try again.")
        }
        return accountID
    }

    func signIn(email: String, password: String) async throws {
        guard !isAuthenticated else { throw StoreFailure.message("Sign out before switching accounts.") }
        try beginWork()
        defer { isBusy = false }
        try await LaunchServices.shared.prepareForLogin()
        let session = try await client.auth.signIn(email: email, password: password)
        guard !session.user.isAnonymous, session.user.email == email,
              client.auth.currentUser?.id == session.user.id else {
            throw StoreFailure.message("Unable to confirm your sign-in. Please try again.")
        }
        do {
            try await openAccount(for: session)
        } catch {
            await clearIdentity()
            try? await client.auth.signOut(scope: .local)
            throw error
        }
    }

    private func openAccount(for session: Session) async throws {
        let attempt = UUID()
        generation = attempt
        let accountID = try await enter(using: client)
        let finishesUpgrade = guestClient.auth.currentUser?.id == session.user.id
        if finishesUpgrade, let previousID = try pendingAccountID(), accountID != previousID {
            throw GuestTransferError()
        }
        let consent = ["consent_version": JSONValue.string(BackendConfiguration.consentVersion)]
        _ = try await request(path: "rest/v1/rpc/travel_action", body: [
            "action": .string("profile.update"),
            "payload": .object(consent)
        ])
        guard generation == attempt else { throw CancellationError() }
        userID = accountID.uuidString.lowercased()
        try await loadSnapshot(generation: attempt)
        guard profile.string("consent_version") == BackendConfiguration.consentVersion else {
            throw StoreFailure.message("Your agreement could not be saved. Please try again.")
        }
        if finishesUpgrade {
            try previousStorage.remove(key: BackendConfiguration.legacySessionKey)
            try companyStorage.remove(key: Self.pendingAccountKey)
            try? await guestClient.auth.signOut(scope: .local)
        }
        isAuthenticated = true
        payments.recoverUnfinished()
        Task { [weak self] in try? await self?.refreshCoinState() }
        await startRealtime()
    }

    func entryErrorMessage(_ error: Error) -> String {
        LaunchServices.shared.network.markTransportFailure(error)
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials: return "The email or password is incorrect."
            case .emailExists, .userAlreadyExists: return "An account with this email already exists. Sign in instead."
            case .overRequestRateLimit: return "Too many attempts. Please try again later."
            default: return authError.localizedDescription
            }
        }
        if error is URLError { return "Check your internet connection and try again." }
        return error.localizedDescription
    }

    private func pendingAccountID() throws -> UUID? {
        if let data = try companyStorage.retrieve(key: Self.pendingAccountKey) {
            guard let value = String(data: data, encoding: .utf8), let id = UUID(uuidString: value) else {
                throw GuestTransferError()
            }
            return id
        }
        guard try previousStorage.retrieve(key: BackendConfiguration.legacySessionKey) != nil else { return nil }
        guard let id = previousClient.auth.currentSession?.user.id else { throw GuestTransferError() }
        try companyStorage.store(key: Self.pendingAccountKey, value: Data(id.uuidString.utf8))
        return id
    }

    private func transferParameters(previousID: UUID?, destination: UUID) async throws -> [String: JSONValue] {
        guard let previousID else { return [:] }
        let linked = try await request(path: "rest/v1/rpc/travel_account_identity", body: [:], using: guestClient)
        if UUID(uuidString: linked.string("account_id")) == previousID { return [:] }
        guard UUID(uuidString: linked.string("account_id")) == destination else { throw GuestTransferError() }
        do {
            let previous = try await previousClient.auth.session
            guard previous.user.id == previousID else { throw GuestTransferError() }
            let ticket: [String: String] = try await previousClient
                .rpc("travel_issue_company_ticket", params: ["destination_id": destination.uuidString])
                .execute().value
            guard let code = ticket["ticket"], code.count == 64 else { throw GuestTransferError() }
            return ["ticket": .string(code)]
        } catch {
            throw GuestTransferError()
        }
    }

    func refresh() async throws {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        try await loadSnapshot(generation: generation)
    }

    func profileStatistics(_ profileID: String) async throws -> Record {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        let attempt = generation
        let result = try await request(path: "rest/v1/rpc/travel_profile_stats", body: ["target_profile": .string(profileID)], optionalRead: true)
        guard generation == attempt else { throw CancellationError() }
        guard result.string("profile_id").lowercased() == profileID.lowercased(),
              ["following", "followers"].allSatisfy({ key in
                  if case .number(let value) = result[key] { return value.isFinite && value >= 0 && value < Double(Int.max) && value.rounded() == value }
                  return false
              }) else { throw StoreFailure.message("Profile statistics could not be loaded.") }
        return result
    }

    @discardableResult
    func perform(_ action: String, _ payload: [String: JSONValue]) async throws -> Record {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        guard !isDeletingAccount else { throw StoreFailure.message("Account deletion is in progress.") }
        let attempt = generation
        let previous = writeTail
        pendingWrites += 1
        isBusy = true
        let operation = Task<Record, Error> { [self] in
            await previous?.value
            guard isAuthenticated, generation == attempt else { throw CancellationError() }
            if action == "safety.hide_place" {
                let result = try await request(path: Self.guideVisibilityPath, body: payload)
                guard generation == attempt else { throw CancellationError() }
                guard case .array = result["hidden_place_ids"] else {
                    throw StoreFailure.message("The server returned an invalid hidden-guide list. Please retry.")
                }
                hiddenPlaceIDs = Set(result.strings("hidden_place_ids"))
                hasGuideVisibility = true
                guideVisibilityVersion = UUID()
                revision += 1
                return result
            }
            let guideRoutes = [
                "guide.unlock": "travel_unlock_guide",
                "guide.submit": "travel_submit_guide",
                "guide.price": "travel_price_guide"
            ]
            if let endpoint = guideRoutes[action] {
                let sandboxUnlock = action == "guide.unlock" && payments.isSandbox
                var parameters = payload
                if sandboxUnlock { parameters["apple_bundle"] = .string(Bundle.main.bundleIdentifier ?? "") }
                let result = try await request(path: "rest/v1/rpc/" + (sandboxUnlock ? "travel_unlock_sandbox_guide" : endpoint), body: parameters)
                guard generation == attempt, result.bool("committed") else {
                    throw StoreFailure.message("The guide change could not be confirmed.")
                }
                do { try await loadSnapshot(generation: attempt) }
                catch is CancellationError { }
                catch { }
                try? await refreshCoinState()
                return result
            }
            let result: Record
            if action == "safety.report", payload["target_kind"]?.string == "guide" {
                var report = payload
                report.removeValue(forKey: "target_kind")
                result = try await request(path: "rest/v1/rpc/travel_report_guide", body: report)
            } else {
                result = try await request(path: "rest/v1/rpc/travel_action", body: ["action": .string(action), "payload": .object(payload)])
            }
            guard generation == attempt else { throw CancellationError() }
            if (action == "safety.report" || action == "safety.block"), !result.bool("committed") {
                throw StoreFailure.message("Your change could not be confirmed. Please try again.")
            }
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

    func refreshCoinState() async throws {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        let attempt = generation
        let environment = payments.resolveEnvironment()
        try await refreshCoinState(environment: environment, generation: attempt)
    }

    private func refreshCoinState(environment: CoinWalletEnvironment, generation attempt: UUID) async throws {
        guard isAuthenticated, generation == attempt, payments.appleEnvironment == environment.rawValue else {
            throw CancellationError()
        }
        let token = UUID()
        coinStateRequest = token
        let sandbox = environment == .sandbox
        let result = try await request(path: environment.statePath,
            body: sandbox ? ["apple_bundle": .string(Bundle.main.bundleIdentifier ?? "")] : [:], optionalRead: true)
        guard generation == attempt, coinStateRequest == token else { throw CancellationError() }
        guard case .number(let total) = result["balance"], total.isFinite, total >= 0,
              total.rounded(.towardZero) == total, total < Double(Int.max),
              case .array = result["activity"], case .array = result["offers"] else {
            throw StoreFailure.message("The coin wallet could not be loaded.")
        }
        balance = Int(total)
        coinActivity = result.records("activity")
        guideOffers = result.records("offers")
        sandboxGuides = sandbox ? result.records("guides") : []
        hasCoinState = true
        revision += 1
    }

    func coinPurchaseStatus(environment: String) async throws -> Record {
        guard isAuthenticated else { throw StoreFailure.authenticationRequired }
        let attempt = generation
        let state = try await request(path: "functions/v1/travel-coin-purchase", body: [
            "action": .string("status_receipt"), "environment": .string(environment),
            "bundle_id": .string(Bundle.main.bundleIdentifier ?? "")
        ], optionalRead: true)
        guard generation == attempt else { throw CancellationError() }
        return state
    }

    func deliverCoinPurchase(transactionID: String, productID: String, receipt: String, account: UUID) async throws {
        guard isAuthenticated, UUID(uuidString: userID) == account else { throw StoreFailure.authenticationRequired }
        let attempt = generation
        let environmentHint = payments.resolveEnvironment()
        let result = try await request(path: "functions/v1/travel-coin-purchase", body: [
            "action": .string("deliver_receipt"),
            "environment": .string(environmentHint.rawValue),
            "bundle_id": .string(Bundle.main.bundleIdentifier ?? ""),
            "transaction_id": .string(transactionID),
            "product_id": .string(productID),
            "receipt_data": .string(receipt)
        ])
        guard generation == attempt, let environment = payments.acknowledgeCoinDelivery(result) else {
            throw StoreFailure.message("Coin delivery could not be confirmed. Please retry.")
        }
        // Discard an earlier read before loading the ledger that actually received the purchase.
        resetCoinState()
        revision += 1
        try await refreshCoinState(environment: environment, generation: attempt)
    }

    private func resetCoinState() {
        coinStateRequest = UUID()
        hasCoinState = false
        balance = 0
        coinActivity.removeAll()
        guideOffers.removeAll()
        sandboxGuides.removeAll()
    }

    func upload(data: Data, contentType: String, purpose: String) async throws -> String {
        guard isAuthenticated, !userID.isEmpty else { throw StoreFailure.authenticationRequired }
        guard !isDeletingAccount else { throw StoreFailure.message("Account deletion is in progress.") }
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
        // Only these inspected editorial portraits may resolve outside project Storage.
        let portraitURLs: Set<String> = [
            "https://images.pexels.com/photos/614810/pexels-photo-614810.jpeg?auto=compress&cs=tinysrgb&w=512&h=512&fit=crop",
            "https://images.pexels.com/photos/733872/pexels-photo-733872.jpeg?auto=compress&cs=tinysrgb&w=512&h=512&fit=crop"
        ]
        if portraitURLs.contains(path), let url = URL(string: path) { return url }
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
        isDeletingAccount = true
        defer { isBusy = false; isDeletingAccount = false }
        await writeTail?.value
        let result = try await request(path: "functions/v1/travel-account", body: ["action": .string("delete")], timeout: 120)
        guard result.bool("deleted") else { throw StoreFailure.message("Account deletion could not be confirmed. Please try again.") }
        // Clear local account state after the service confirms deletion.
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
        let visibilityVersion = guideVisibilityVersion
        do {
            async let statistics = try? request(path: "rest/v1/rpc/travel_content_stats", body: [:], optionalRead: true)
            async let visibility = try? request(path: Self.guideVisibilityPath, body: [:], optionalRead: true)
            var value = try await request(path: "rest/v1/rpc/travel_snapshot", body: [:])
            // The snapshot includes the first 2,000 rows of each catalog in ID order.
            for table in ["clips", "places"] where value[table].array.count == 2000 {
                value[table] = try await completeWorkCatalog(table, firstPage: value[table].array)
            }
            let guideState = await visibility
            let latestStatistics = await statistics
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
            if visibilityVersion == guideVisibilityVersion,
               let guideState, case .array = guideState["hidden_place_ids"] {
                hiddenPlaceIDs = Set(guideState.strings("hidden_place_ids"))
                hasGuideVisibility = true
            }
            workLikeCounts = indexWorkLikes(latestStatistics)
            snapshot = value
            profile = value.record("profile")
            lastRefreshError = nil
            revision += 1
        } catch {
            guard generation == attempt, snapshotRequest == requestID, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
                throw CancellationError()
            }
            lastRefreshError = error.localizedDescription
            revision += 1
            throw error
        }
    }

    private func completeWorkCatalog(_ table: String, firstPage: [JSONValue]) async throws -> JSONValue {
        var catalog = firstPage
        var cursor = firstPage.compactMap { $0.object["id"]?.string }.max() ?? ""
        while !cursor.isEmpty {
            try Task.checkCancellation()
            let page: [Record] = try await client.from(table).select()
                .gt("id", value: cursor).order("id").limit(500).execute().value
            guard let last = page.last else { break }
            for row in page {
                var columns = row.values
                let data = columns.removeValue(forKey: "data")?.object ?? [:]
                catalog.append(.object(data.merging(columns) { _, column in column }))
            }
            cursor = last.id
        }
        return .array(catalog)
    }

    private func request(path: String, body: [String: JSONValue], optionalRead: Bool = false, timeout: TimeInterval = 30, using source: SupabaseClient? = nil) async throws -> Record {
        let session = try await (source ?? client).auth.session
        var request = URLRequest(url: BackendConfiguration.projectURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = optionalRead ? 5 : timeout
        request.setValue(BackendConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if !optionalRead { LaunchServices.shared.network.markTransportFailure(error) }
            throw error
        }
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
            // The snapshot loader publishes failures while the request is still current.
            try? await self.refresh()
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
        workLikeCounts.removeAll()
        snapshot = Record()
        hiddenPlaceIDs.removeAll()
        hasGuideVisibility = false
        guideVisibilityVersion = UUID()
        resetCoinState()
        payments.reset()
        lastRefreshError = nil
        realtimeError = nil
        revision += 1
    }
}

// Keep the SDK's existing item format and service names for guests who upgrade.
private struct GuestCredentialStorage: AuthLocalStorage {
    let service: String

    private func query(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func retrieve(key: String) throws -> Data? {
        var request = query(for: key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw StoreFailure.message("Your saved sign-in could not be read. Unlock your device and try again.")
        }
        return data
    }

    func store(key: String, value: Data) throws {
        try KeychainLocalStorage(service: service).store(key: key, value: value)
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreFailure.message("Your saved sign-in could not be cleared. Unlock your device and try again.")
        }
    }
}

// Email sign-in lasts for this app process. Only pre-upgrade guests rely on Keychain.
private final class EmailSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        lock.withLock { values[key] = nil }
    }
}

struct GuestTransferError: LocalizedError {
    var errorDescription: String? { "Your saved account could not be restored. Please try again." }
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
