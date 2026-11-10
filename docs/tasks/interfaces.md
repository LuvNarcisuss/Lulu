# Shared Interfaces

This contract is binding across independent feature work. Contact the coordinator before changing shared names. All IDs are server UUID strings. All timestamps use ISO 8601. Records are flat JSON dictionaries; nested arrays/objects use JSONValue. Record.swift is already supplied by the coordinator.

## Backend store (backend worker owns implementation)

```swift
@MainActor final class TravelStore: ObservableObject {
    @Published private(set) var revision: Int
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var isBusy: Bool
    @Published private(set) var profile: Record
    var userID: String { get }
    var balance: Int { get }
    init()
    func rows(_ key: String) -> [Record]
    var hasSavedSession: Bool { get }
    var savedSessionIsGuest: Bool { get }
    func signInWithOneTap() async throws
    func refresh() async throws
    @discardableResult func perform(_ action: String, _ payload: [String: JSONValue]) async throws -> Record
    func upload(data: Data, contentType: String, purpose: String) async throws -> String
    func mediaURL(_ path: String) async throws -> URL
    func signOut() async throws
    func deleteAccount() async throws
}
```

`perform` refreshes committed state and increments revision after successful writes. It must preserve the operation's success if a later refresh fails, exposing refresh failure separately. No UI success before persistence. Upload returns object path, never temporary signed URL. Media URL resolves public catalog paths and authorized private uploads. Store handles real Auth, realtime subscriptions, refresh, reconnection and user isolation. No seeded private data.

Snapshot keys: `clips`, `places`, `guides`, `profiles`, `likes`, `saved_clips`, `saved_places`, `comments`, `follows`, `blocks`, `reports`, `journeys`, `conversations`, `messages`, `chat_preferences`, `submissions`, `wallet_activity`.

## Record fields

- profile: id, display_name, bio, avatar_path, is_editorial, source_url, consent_version. `profiles` includes editorial publishers (never auth users) and discoverable real members. Only actual members support chat. Profile lookup uses id.
- clip: id, title, caption, place_id, publisher_id, video_path, cover_path, source_url, author, duration, category, optional positive feed_rank for discovery order. No invented base likes/comments.
- place: id, name, city, country, region (`Europe` or `North America`), category, latitude, longitude, summary, photo_path, source_url, best_time, practical_tip.
- guide: id, place_id, title, intro, sections (array of {title,body}), source_name, source_url, reading_minutes.
- likes/saved_clips: id, clip_id, user_id. saved_places: id, place_id, user_id.
- comment: id, clip_id, user_id, body, parent_id (nullable), created_at.
- follow: id, follower_id, following_id. block: id, blocker_id, blocked_id. report: id, user_id, target_kind, target_id, reason, details, created_at.
- journey: id, owner_id, title, start_date, end_date, currency, budget (number), days (array), checklist (array), notes, updated_at. A day is {id,date,title,stops:[{id,place_id,note}],note}. Checklist is [{id,title,done}]. Client makes stable UUIDs; server checks ownership and fields.
- conversation: id, title, is_group, member_ids (string array), updated_at, last_message, unread_count.
- message: id, conversation_id, sender_id, body, attachment_path (nullable), attachment_type (nullable), reply_to (nullable), created_at. Actual server persistence is `Sent`; do not invent Delivered.
- chat_preference: id, conversation_id, user_id, pinned, muted, archived, draft, last_read_at.
- submission: id, owner_id, title, caption, video_path, cover_path, place_id (nullable), status, created_at. Private pending moderation.
- wallet_activity: id, owner_id, kind, amount, created_at, description. No client minting.

## Authoritative actions

All payload keys below are snake_case. Optional IDs use null when absent. Every action validates auth, ownership, content lengths, relationships and membership on the server.

- `profile.update`: display_name, bio, avatar_path (optional), consent_version (optional).
- `clip.like` / `clip.save`: clip_id, enabled (bool).
- `place.save`: place_id, enabled.
- `safety.hide_place`: place_id, enabled. The store routes this action to the separate `travel_guide_visibility` RPC. Calling that RPC without arguments returns the viewer's `hidden_place_ids`.
- `comment.add`: clip_id, body, parent_id (nullable); `comment.delete`: comment_id.
- `relationship.follow`: profile_id, enabled.
- `safety.block`: profile_id, enabled; `safety.report`: target_kind, target_id, reason, details; `safety.unreport`: report_id.
- `journey.save`: full journey fields above (without owner_id); `journey.delete`: journey_id.
- `chat.direct`: profile_id; returns conversation_id. Canonical pair, never duplicate threads.
- `chat.group`: title, member_ids (at least two other real members); returns conversation_id.
- `chat.send`: id (client-generated stable UUID idempotency key), conversation_id, body, attachment_path (nullable), attachment_type (nullable), reply_to (nullable).
- `chat.preferences`: conversation_id, pinned/muted/archived/draft/last_read_at (partial keys preserve unspecified fields).
- `submission.create`: id, title, caption, video_path, cover_path, place_id (nullable); `submission.delete`: submission_id.
- `guide.submit`, `guide.price` and `guide.unlock` route to isolated authenticated guide RPCs. `travel_coin_state` returns the wallet balance, activity and available guide offers. Apple delivery uses `travel-coin-purchase`. Its service-only credit RPC is unavailable to app clients.

## Shared UIKit design (coordinator owns implementation)

`TravelScreen: UIViewController` has `let store: TravelStore`, `let content: UIStackView`, `let scroll: UIScrollView`, `init(store: TravelStore)`, `func render()` (override; base clears content), `func push(_ controller: UIViewController)`, `func run(_ work: @escaping () async throws -> Void)` (busy guard + visible error, retains fields), `func notice(_ message: String)`, `func confirm(_ title: String, message: String, destructive: Bool = false, action: @escaping () -> Void)`. Base subscribes to revision and calls render only while visible; feature controllers may override to preserve active inputs. Pushed screens hide the floating dock.

Global helpers (UIKit, @MainActor):
- `text(_ value: String, _ size: CGFloat = 16, color: UIColor = Palette.ink, display: Bool = false) -> UILabel`
- `column(_ views: [UIView] = [], spacing: CGFloat = 16) -> UIStackView`
- `line(_ views: [UIView] = [], spacing: CGFloat = 12) -> UIStackView` (horizontal)
- `card(_ views: [UIView], color: UIColor = Palette.paper) -> UIView` (padded vertical stack)
- `action(_ title: String, icon: String? = nil, filled: Bool = true, _ handler: @escaping () -> Void) -> UIButton`
- `iconButton(_ name: String, label: String, _ handler: @escaping () -> Void) -> UIButton`
- `input(_ placeholder: String, value: String = "") -> UITextField`
- `remoteImage(_ path: String, store: TravelStore, height: CGFloat, radius: CGFloat = 20) -> RemoteImageView`
- `spacer(_ height: CGFloat = 8) -> UIView`
- `FontBook.font(_ size: CGFloat, display: Bool = false) -> UIFont`
- `Palette.ink`, `.muted`, `.teal`, `.cream`, `.paper`, `.ochre`, `.coral`, `.line`.

Generated image asset names: `icon-shorts`, `icon-explore`, `icon-journeys`, `icon-chats`, `icon-profile`, `icon-search`, `icon-add`, `icon-back`, `icon-close`, `icon-heart`, `icon-comment`, `icon-save`, `icon-share`, `icon-more`, `icon-location`, `icon-map`, `icon-calendar`, `icon-check`, `icon-wallet`, `icon-diamond`, `icon-settings`, `icon-edit`, `icon-camera`, `icon-photo`, `icon-send`, `icon-group`, `icon-pin`, `icon-mute`, `icon-trash`, `icon-report`, `icon-block`, `icon-phone`, `icon-video`, `icon-refresh`, `icon-route`, `icon-globe`. `background-paper`, `background-welcome` and optional `background-wallet`. No system icon fallback.

## Feature controller routes

- Coordinator: `ShortsController(store:)`, `ExploreController(store:)`, `JourneysController(store:)`.
- Social/profile worker: `ChatsController(store:)`, `MeController(store:)`, `PublicProfileController(store:profileID:)`, `ConversationController(store:conversationID:)`, `WalletController(store:)`, `SettingsController(store:)`, `ReportController(store:kind:targetID:)`.
- Coordinator: `ClipFeedController(store:clips:initialIndex:)`, `PlaceController(store:placeID:)`, `JourneyDetailController(store:journeyID:)`, `CreationController(store:)`.
- Profile worker may route saved/personal clips through ClipFeedController; places through PlaceController; journey records through JourneyDetailController.

Keep file ownership boundaries. Do not compile/typecheck/run an app or simulator. Static inspection only; backend worker may run finite API checks under the authorized stage A skill.
