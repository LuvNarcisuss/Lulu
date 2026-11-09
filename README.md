# Travel Application

An unnamed native iPhone travel application with five destinations: **Shorts**, **Explore**, **Journeys**, **Chats** and **Me**. The owner's display name and App Store product IDs are intentionally unconfigured. `TravelApp` is the engineering target and scheme.

Open `TravelApp/TravelApp.xcodeproj` to inspect the project. Configuration originates in `TravelApp/project.yml`; XcodeGen regenerates metadata without compiling. The project uses iOS 16+, Swift 5 language mode, UIKit, AVFoundation, MapKit, PhotosUI, StoreKit, Supabase Swift and Alamofire. Only iPhone portrait is supported.

## Product behavior

- Shorts offers real recorded travel films, search and regional filtering, single-player vertical paging, pause, seek, sound and framing controls, destination links, real likes/comments/replies/saves, source sharing, report/block and private video submissions.
- Explore combines a destination map and filtered list with real photographs, independently written travel notes, official tourism sources, saves, Apple Maps directions and itinerary connections.
- Journeys keeps private dated itineraries, ordered stops, per-stop/day notes, packing checklists, estimated budgets and journal notes. Date changes preserve retained day records and ask before dropping populated days.
- Chats uses actual discoverable members, canonical direct threads, groups, persistent text/photo/reply messages, realtime updates, drafts, read state, pinned/muted/archived preferences, member safety controls and camera-based friend codes. It does not simulate connected voice/video calls or remote read receipts.
- Me includes profile editing, actual works/liked/saved/pending collections, private submission playback, source credits, agreements, safety history and a zero-initial-balance wallet. Seven diamond packages remain unavailable because owned products and verified purchase delivery are not configured.

## Content and visual resources

The initial catalog contains **11 distinct real videos and covers, 12 destinations, 12 original English guides and 14 real photographs**. Video and photography source, license, processing, inspection and SHA-256 records live in `Assets/media-manifest.json`. The catalog is uploaded to this application's own Supabase Storage; business media is not bundled or used as an offline business-data fallback.

The image model generated **36 transparent icons, two watercolor/paper backgrounds and a dedicated opaque 1024-pixel AppIcon**. Generation prompts and engine records live in `Assets/generated/generation-record.json`. Packaged Kalam and a licensed, statically instantiated Fraunces display font supply app-owned typography; the app does not substitute system fonts or SF Symbols. System-owned Photos, Maps, sharing and permission surfaces retain their own rendering.

## Backend and entry

The dedicated Supabase project is `dlbaneeshycwmhgfeokx`, named `travel-social-20261103`, in `eu-west-1`, under the owner-selected 139 organization. Its dashboard is https://supabase.com/dashboard/project/dlbaneeshycwmhgfeokx.

The selected workflow is `ios-swift-supabase-one-tap`, **stage A**. One explicit login button restores the existing real guest session or creates one only when no session exists, then calls the authenticated `travel-entry` function and reads actual business state. Network errors do not create replacement accounts. Cold launches retain welcome and explicit entry. A separate project-scoped Keychain installation UUID is preserved independently of Auth. Signing out deliberately ends guest access and warns that an unlinked guest may be unrecoverable.

Public editorial publishers are not fabricated member accounts. New real accounts start with empty personal records, an empty inbox and zero diamonds. Server-side actions validate ownership, membership, blocking, idempotency and direct-message greeting limits. Private data has RLS; raw unauthenticated roles cannot execute business RPCs. Failed server reads show an opaque error/retry surface instead of displaying previous server content as a fallback; unfinished user input remains in place.

Stage B external authentication, external Socket, WebView and purchase forwarding have not been requested or implemented. This app has no AI feature. See `docs/backend/integration.md` for deployment and finite backend verification evidence.

## Owner configuration still required

- Final app display name, registered Bundle ID and development team. The current `com.configure.travelapp` value is an explicitly unregistered engineering identifier.
- Owned consumable product IDs, product amounts/prices confirmation, authoritative verified purchase delivery and actual Apple environment acceptance. The current code only discovers real products and does not start payments or mint diamonds.
- Signing and APNs entitlement configuration before push registration is enabled. Registration callbacks are prepared, but background notifications are not claimed as operational.
- Legal operator and a real staffed contact channel before public distribution. Current agreements accurately disclose the unassigned identity and current capabilities.
- Explicit authorization to deploy the self-account deletion service. Automatic review rejected that deployment because destructive account/data effects had not been explicitly authorized. The function source is provided, deployment is absent, and the UI accurately marks deletion unavailable.

## Verification boundaries

Static resource/configuration checks, Swift grammar parsing, XcodeGen metadata generation and an independent static review were performed. Finite isolated Supabase API, permissions, media and realtime checks are recorded separately under `docs/backend/`.

**No Swift compilation, typecheck, dependency resolution, application launch, simulator, Preview, UI runtime test, local StoreKit Test, Apple sandbox purchase or production purchase was performed.** These actions require the owner's explicit authorization. A syntax parse is not a build or typecheck, and backend protocol verification is not iPhone UI acceptance.

Run permitted static inspection with `python3 scripts/static_audit.py` and `python3 scripts/media_verify.py`. `scripts/swift_syntax_audit.py` requires the separately installed `tree-sitter` and `tree-sitter-swift` Python packages and parses grammar only. Do not infer runtime success from these commands.

Current design and scope: `docs/superpowers/specs/2026-11-03-travel-app.md`. Shared interfaces: `docs/tasks/interfaces.md`. Implementation plan: `docs/superpowers/plans/2026-11-03-travel-app.md`.
