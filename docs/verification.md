# Delivery Verification

Original delivery date: November 3, 2026. The application is now named Lulu. This record separates static evidence from real backend checks and unperformed app acceptance.

## Lulu identity update

The displayed name and bundle name are Lulu. The internal target and product identifiers remain TravelApp. The current project is `LuluApp/Lulu.xcodeproj`.

## November 16 purchase verification

The owner authorized real-device Apple sandbox testing on iPhone 12 and confirmed com.lulu.tourtravel / Apple ID 6832914128. Current scoped results supersede earlier payment and build statements below. See [purchase repair evidence](runtime-acceptance/2026-11-16-1030-purchase-repair/README.md) for the actual build, seven local StoreKit test results, 18 handler tests, isolated SQL/signature regressions, and remaining real sandbox delivery blockers. Earlier sections retain their original dates and scopes.

## Original static evidence

- XcodeGen successfully generated `TravelApp/TravelApp.xcodeproj` from the current configuration. This is metadata generation, not compilation.
- Source/resource/configuration inspection passed with 22 Swift source files. `static-audit.json` contains the current assertion count and scope.
- Tree-sitter Swift grammar parsing reported zero syntax error nodes in those 22 files. This does not validate Swift types, SDK availability, linking or runtime behavior.
- Info.plist and generated project plist syntax were inspected. The target is iPhone-only, iOS 16+, Swift 5 language mode and portrait, with Catalyst, Mac compatibility and Vision compatibility disabled.
- Generated image files, 36 icon references, the AppIcon, custom-font registration, source/media hashes, catalog IDs and media-to-record references were checked. `media/static-inspection.json` and `media/README.md` hold evidence.
- Independent static review and scoped startup review found input-preservation, media filtering, journey-date and network-readiness issues. Corrected source was recorded in `tasks/independent-review.md`; no device behavior is inferred from that review.
- A credential-value scan found no privileged Supabase key or JWT token value in authored client, backend source, scripts or documentation. The client includes only the project's publishable key.
- Actual host version was read without building: Xcode 26.0.1 and Swift compiler 6.2. Supabase 2.55.6's exact official tag declares tools 6.1, and Alamofire 5.10.2 declares tools 6.0. Dependency resolution and transitive compatibility remain unexecuted.

## Deployed backend evidence

The dedicated project `dlbaneeshycwmhgfeokx` contains 18 RLS-enabled public tables and the active authenticated `travel-entry` function. Explicit grants deny raw unauthenticated execution of business RPCs while permitting authenticated guest identities. Final read-only aggregate SQL confirms 2 editorial publishers, 12 places, 11 clips, 12 guides, 36 catalog media objects, 2 legal objects and no test uploads, messages, journeys or submissions.

Finite isolated checks covered real guest Auth and restored-user APIs; exact source-to-catalog field comparisons; zero initial balance and personal empty state; actual profile/social/comment/journey/submission writes and readback; cross-account restrictions; private object ownership and participant access; canonical/idempotent messaging; greeting/mutual/group rules; dual-party live events, reconnect/history and nonmember exclusion. See `backend/integration.md` and its linked JSON reports for exact scope.

Every catalog object passed anonymous full GET, size and SHA-256 comparison. Both legal PDFs passed anonymous HTTP 200, application/pdf, byte-hash equality and English text/page inspection, and matching files are bundled. The consent version is derived from their combined PDF bytes. The documents are frozen after this delivery unless the owner explicitly requests changes.

The owner explicitly approved cleanup of the three temporary verification accounts. Their Auth identities, associated fixture data, two empty test conversations and verification uploads have been removed. Final counts are in `backend/final-summary.json`. No catalog or legal object was removed during cleanup.

## Unperformed and unavailable

No Swift compilation, typechecking, dependency resolution, app launch, Simulator, Preview, UI test, device acceptance, StoreKit Test, Apple sandbox purchase or production purchase was executed. The owner has not authorized these operations. There is no claim that the project builds, that layouts have been observed on iPhone, or that Apple products can be purchased.

See [Coins and paid guides](backend/coins-and-guides.md) for current hosted payment and content evidence. Apple App ID configuration, App Store Connect availability and signed runtime acceptance remain separate. APNs callbacks are implemented but registration is disabled while signing entitlement configuration is absent. Connected voice/video calling, live broadcasting and AI are not implemented or represented as available.

The self-account deletion source is present but its persistent service was not deployed: automatic approval review rejected the destructive endpoint without explicit owner authorization. The owner's later authorization covered only the three temporary verification accounts, so it was not reused to deploy this endpoint. Settings displays the actual unavailable state. This unresolved deployment and unperformed compilation prevent a claim of complete stage-A release acceptance.
