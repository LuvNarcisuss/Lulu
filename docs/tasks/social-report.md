# Social and Profile Implementation

## Delivered routes

- `ChatsController`: empty first inbox, All/Unread/Pinned/Drafts filters, retained search, archived conversation view, manual refresh and authoritative preference controls. Direct rows use the actual other member avatar or a generated profile placeholder. Group rows use up to nine distinct actual member avatars, never borrowed portraits, and show recent timestamps.
- `MemberDiscoveryController`: actual non-editorial public members, name/full-ID search, canonical server direct conversation creation and named groups requiring at least two distinct other eligible members.
- `FriendScannerController` and `TravelerCodeController`: navigation-plus entry, actual AVCapture QR metadata scanning, explicit camera authorization, serial camera lifecycle off the main thread, stop on exit/background, own-ID QR generation/sharing, full-ID fallback, strict friend-code parsing and authoritative actual-member resolution. No scanner URL is opened as a website.
- `ConversationController`: fixed keyboard-adjacent composer, independently scrolling messages, automatic bottom anchoring only when already near the bottom, an explicit New messages action when reading older content, preserved reply/text state, server messages, stable client send IDs, replies, bounded photo attachment import/upload, retained failed input, serialized debounced server draft saves, private read-state writes and member/profile navigation. Incoming refresh preserves the composer subtree. No fabricated replies, delivery receipts, online indicators or connected calls.
- `MeController`: actual account identity, record-derived counts, published works, liked videos, saved videos and places, submission review statuses, private submission playback through `ClipFeedController` with `is_private=true` and the current owner as publisher, creation, profile editing, settings and wallet routes.
- `PublicProfileController`: real/editorial distinction, record-derived counts and works, authoritative follow/block/report actions and canonical direct messaging for eligible real members only.
- `SettingsController`: profile editor, blocked profiles, submitted reports and withdrawal, source credits, Terms/Privacy PDF reader, guest access-loss warning, logout and own-account deletion confirmation.
- `ReportController`: retained reason/details form, bounded details and saved-report success only after `perform` succeeds.
- `WalletController`: server balance and activity only, seven configured diamond tiers, real Apple product discovery/localized prices, retry, and disabled charging while authoritative purchase delivery is absent.

## Implementation boundaries

Only `TravelApp/Sources/Features/Social/`, `TravelApp/Sources/Features/Profile/` and this report were authored by the social/profile worker. Shared design, store, shell, backend, catalog configuration and generated assets remain coordinator/backend ownership.

`PaymentCatalogAdapter` reads bundled `PaymentCatalog.json` with `tiers` entries containing `diamonds` and `productID`. Empty IDs make every offer unavailable. It never submits payments, handles a simulated purchase or mints credit. Even future returned products remain non-purchasable until a separately implemented verified delivery contract exists.

`AgreementController` reads `termsURL`/`privacyURL` from bundled `BackendConfig.json`, requires HTTPS/PDF responses and supports flattened bundled `TermsOfService.pdf`/`PrivacyPolicy.pdf`. Missing agreement configuration is reported honestly; no operator identity or support contact is invented.

Photo import consumes the Photos provider's temporary file within its validity window, enforces a 30 MB source limit, downsamples to at most 1,600 pixels and generates JPEG bytes bounded at 5 MB. Upload occurs through the store before `profile.update` or `chat.send`. Account identity is rechecked after upload. Photos originals are never removed.

Draft writes are serialized independently from typing. Failed saves retain composer text and expose a failure. Draft state is flushed when leaving the conversation, bounded at 2,000 characters and published as saved only after persistence. Photo/reply selections remain attached to an open composer and are not falsely described as durable drafts across process termination.

## Static evidence

On November 3, 2026, static source assertions passed for ten Swift files, all seven required public controller routes and 27 contracted generated raster icon names. The assertions checked English source content, trailing whitespace, absence of system-font/system-icon/native-alert substitutions, expected chat actions, composer-preserving refresh, fixed composer constraints, near-bottom scrolling policy, capture permission/background stop paths, QR generator usage, bounded distinct group avatar selection, private-playback routing and absence of payment submission calls. Manual source review covered async callbacks, stable message IDs, retained forms, temporary-file lifetime, canonical conversation response handling and the navigation lifecycle of options screens.

These checks are source inspection only. No Swift compilation, typechecking, application launch, simulator, Preview or runtime test was invoked. This report is not runtime or service acceptance.

## Open dependencies

- The backend worker confirmed `chat`/`avatar` upload purposes, `image/jpeg` attachment type and `message`/`profile` report targets. Backend deployment, authoritative RLS, actual member discovery, realtime reconnection, private read state and isolated API acceptance belong to the backend task.
- The requested server policy permits one greeting for a non-mutual direct pair and unlimited messages after mutual following; group messages remain unaffected. The UI explains that the server checks this limit. Backend enforcement was requested separately and must not be inferred from this UI implementation.
- The coordinator must include camera permission text and the `travelapp` URL scheme. Optional incoming-scheme handling can reuse `TravelFriendCode.memberID(from:)` and must still resolve an actual non-editorial member. Camera permission outcomes, capture interruptions, QR detection and generated QR scanning have not been executed.
- Private submission records are flagged for the coordinator-owned feed to suppress public reactions/sharing and display actual private review status.
- Record-derived public counts depend on snapshot coverage supplied by the server; no invented base engagement is added.
- Actual Apple catalog availability, owned product IDs, registered bundle/team identity, production purchase verification and wallet delivery remain unavailable/unverified.
- Published legal documents require owner-selected operator details and the coordinated backend/PDF configuration.
- Runtime layout, keyboard behavior, Dynamic Type, VoiceOver, photo-provider failures, concurrent drafts/messages and actual device/network behavior remain unexecuted acceptance work.
