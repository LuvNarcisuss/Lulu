# Lulu

Lulu is a native iPhone travel application with five destinations: **Shorts**, **Explore**, **Journeys**, **Chats** and **Me**. The nine coin packages use the owner-confirmed mapping and two new identifiers. The Xcode project and sole shared scheme are `Lulu`. The internal target, product and Swift module are `TravelApp`.

Open `LuluApp/Lulu.xcodeproj` to inspect the project. Configuration originates in `LuluApp/project.yml`; XcodeGen regenerates metadata without compiling. The project uses iOS 16+, Swift 5 language mode, UIKit, AVFoundation, MapLibre, MapKit, PhotosUI, StoreKit, Supabase Swift and Alamofire. Only iPhone portrait is supported.

## Product behavior

- Shorts opens directly into autoplay with a single player and vertical paging. The toolbar opens search, regional filters, and video creation. The feed offers pause, seek, sound and framing controls, destination links, real likes/comments/replies/saves, source sharing, report/block and private video submissions.
- Explore switches between an English OpenFreeMap street map and a filtered destination list with real photographs, independently written travel notes, official tourism sources, saves, Apple Maps directions and itinerary connections.
- Journeys keeps private dated itineraries, ordered stops, per-stop/day notes, packing checklists, estimated budgets and journal notes. Date changes preserve retained day records and ask before dropping populated days.
- Chats uses actual discoverable members, canonical direct threads, groups, persistent text/photo/reply messages, realtime updates, drafts, read state, pinned/muted/archived preferences, member safety controls and camera-based friend codes. It does not simulate connected voice/video calls or remote read receipts.
- Me includes profile editing, actual works/liked/saved/pending collections, private submission playback, source credits, agreements, safety history and a zero-initial-balance wallet. The wallet displays nine coin packages. Apple supplies storefront prices and the production verifier gates checkout.

## Content and visual resources

The catalog contains **14 distinct real videos and covers, 12 destinations, 12 original English guides and 14 real photographs**. Video and photography source, license, processing, inspection and SHA-256 records live in `Assets/media-manifest.json`. The catalog is uploaded to this application's own Supabase Storage; business media is not bundled or used as an offline business-data fallback.

The image model generated **36 transparent icons, two watercolor/paper backgrounds and a dedicated opaque 1024-pixel AppIcon**. Generation prompts and engine records live in `Assets/generated/generation-record.json`. Packaged Kalam and a licensed, statically instantiated Fraunces display font supply app-owned typography; the app does not substitute system fonts or SF Symbols. System-owned Photos, Maps, sharing and permission surfaces retain their own rendering.

## Backend and entry

The dedicated Supabase project is `dlbaneeshycwmhgfeokx`, named `travel-social-20261103`, in `eu-west-1`, under the owner-selected 139 organization. Its dashboard is https://supabase.com/dashboard/project/dlbaneeshycwmhgfeokx.

The stage A entry screen uses one-tap guest sign-in after explicit consent on the welcome page. It restores a saved session or creates an anonymous account when none exists. The authenticated `travel-entry` function, consent write and account snapshot must succeed before the home screen opens. The Apple entitlement is present in the source. Hosted Auth setup and verification status are documented in [One-Tap Sign-In](docs/backend/sign-in.md).

Public editorial publishers are not fabricated member accounts. New real accounts start with empty personal records, an empty inbox and zero coins. Server-side actions validate ownership, membership, blocking, idempotency and direct-message greeting limits. Private data has RLS; raw unauthenticated roles cannot execute business RPCs. Failed server reads show an opaque error/retry surface instead of displaying previous server content as a fallback; unfinished user input remains in place.

Stage B external authentication, external Socket, WebView and purchase forwarding have not been requested or implemented. This app has no AI feature. See `docs/backend/integration.md` for deployment and finite backend verification evidence.

## Owner configuration still required

- Apple registration and distribution signing for `com.lulu.tourtravel`. Confirm that the App Store Connect record with Apple ID `6832914128` uses this Bundle ID before building with Codemagic.
- Apple App ID configuration, App Store Connect registration for the nine consumables and actual Apple environment acceptance. See [Coins and paid guides](docs/backend/coins-and-guides.md).
- Signing and APNs entitlement configuration before push registration is enabled. Registration callbacks are prepared, but background notifications are not claimed as operational.
- Publish the revised [Lulu agreements](docs/backend/legal/2026-11-09-lulu/README.md) at the existing URLs and review the account wording before public distribution.
- Explicit authorization to deploy the self-account deletion service. Automatic review rejected that deployment because destructive account/data effects had not been explicitly authorized. The function source is provided, deployment is absent, and the UI accurately marks deletion unavailable.

## Verification boundaries

Static resource/configuration checks, Swift grammar parsing, XcodeGen metadata generation and an independent static review were performed. Xcode 26.0.1 resolved the Lulu scheme’s Swift packages, and the project’s shared Package.resolved records the verified versions. Finite isolated Supabase API, permissions, media and realtime checks are recorded separately under `docs/backend/`.

The owner-authorized November 10 simulator run built and launched Lulu and exercised selected flows across all five tabs. The [functional acceptance report](docs/runtime-acceptance/2026-11-10-1154-full-functional.md) records the scenarios, fixes, and remaining gaps. Apple sandbox and production purchases remain unverified.

Run permitted static inspection with `python3 scripts/static_audit.py` and `python3 scripts/media_verify.py`. `scripts/swift_syntax_audit.py` requires the separately installed `tree-sitter` and `tree-sitter-swift` Python packages and parses grammar only. Do not infer runtime success from these commands.

Current design and scope: `docs/superpowers/specs/2026-11-03-travel-app.md`. Shared interfaces: `docs/tasks/interfaces.md`. Implementation plan: `docs/superpowers/plans/2026-11-03-travel-app.md`.
