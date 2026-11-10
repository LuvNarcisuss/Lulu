# Backend Integration

Lulu returned to anonymous one-tap entry on November 9. See [One-Tap Sign-In](sign-in.md) for the current client flow and hosted settings. The original deployment evidence remains recorded here.

Status: stage A deployed and finite backend verification passed for the implemented application data, media and IM paths. Account-deletion deployment requires explicit owner approval. The owner subsequently approved cleanup of the three isolated Auth verification identities, which were removed through the official dashboard. Application build and device acceptance are not authorized and have not been performed. This is not a claim that every stage A release prerequisite is complete.

## Dedicated project

- Account link: 139 (`link_6ae9a0dba46881918588c741c7d6c89f`).
- Organization: aelm102100@139.com's Org (`wuwstedwrsfrxkbxjuqa`).
- Created specifically for this application: `travel-social-20261103`, ref `dlbaneeshycwmhgfeokx`, region `eu-west-1`, Free plan, observed `ACTIVE_HEALTHY`.
- Origin: `https://dlbaneeshycwmhgfeokx.supabase.co`.
- Creation attempt was recorded before creating the project in `supabase-plan.json`. No other application's project, identity, credits, products, contacts, credentials or data was copied. The creation tool did not request a cost confirmation.
- The app is named Lulu, and its Release Bundle ID is `com.lulu.tourtravel`. Apple registration and the development team remain unconfirmed. See [Coins and paid guides](coins-and-guides.md) for the current product mapping and verification requirements.

## Deployed contract

`supabase/migrations/20261103080000_travel_stage_a.sql` defines 18 RLS-protected application tables, relationship uniqueness/FKs, owner and member predicates, authoritative `travel_action`, idempotent profile bootstrap, bounded `travel_snapshot`, Storage buckets and message/membership/conversation Postgres Changes publication. The coordinator successfully applied the source migration and the explicit anon-execution revocation followup. `schema-verification.json` records live RLS and role privileges. Direct client INSERT and raw `anon` RPC execution are unavailable.

`travel-entry` Edge Function is ACTIVE version 1 (ID `e9b05213-0fa1-49ed-9f6c-1b4687b38926`, source SHA-256 `249e31d79252726fff0b2cf1bb778b2a9a95b376908e667c1bbceabb85f6ff2c`). Its handler validates the user's token with Supabase Auth, invokes `travel_bootstrap` in that user's context and returns exactly the A response `{"code":0,"message":"ok","data":{}}`. It does not use a service-role client or contact an external authentication system. The gateway's JWT switch is disabled because the handler performs actual Auth validation; anonymous and malformed-token requests were verified as HTTP 401.

During the original stage A deployment, Anonymous Sign-Ins were enabled and saved in this project's dashboard. `TravelStore` uses official Supabase Swift exactly 2.55.6, whose tag archive manifest requires Swift tools 6.1; the development machine's compiler is 6.2. SDK package resolution and compilation have not been executed. Authentication uses the SDK's project-scoped Keychain storage. The original login waited for `LaunchServices.prepareForLogin`, restores/refreshed sessions through `auth.session`, creates an anonymous account only on `AuthError.sessionMissing`, calls the authenticated entry function, validates the snapshot and starts realtime listeners. HTTP/SDK transport errors invalidate the shared network gate without automatic reauthentication.

Explicit sign-out uses the SDK's local sign-out. It removes saved credentials and visible account state while preserving the separate device identifier. It does not promise guest recovery afterward. Only an eventual external-session expiry in stage B would have different semantics; stage B is absent here.

Writes are serialized. Owner IDs, status, balance and creation timestamps are server controlled; personal state is published only after successful persistence. A committed action remains successful if its subsequent refresh fails, with `lastRefreshError` exposed independently. Snapshots are retained only during in-flight requests and replaced atomically; the shell masks server content with a retry error after actual read failure. Generation/request checks reject stale completions. No bundle catalog, seeded private data, offline business fallback, fabricated responses, fake delivery or client balance minting is used.

## Guide safety

The hosted `20261110014316_guide_visibility` migration adds the account-owned `guide_visibility` table and `travel_guide_visibility` RPC. Hide and restore update the viewer's preference without changing the public catalog, saved places, trips, or reports. The existing report RPC accepts the place ID, and video safety uses the existing clip-report and publisher-block routes. The hosted function definitions for `travel_action` and `travel_snapshot` retained their previous hashes.

Remote inspection confirmed row-level security, three owner policies, caller-context execution, and authenticated-only RPC access. A read-only request with an isolated test claim returned an empty hidden-guide list. No account or guide preference was written during that check. App runtime acceptance remains pending.

## Catalog and media

On November 9, three portrait films and their covers were added under `catalog/shorts-2026-11-09/`. The current catalog has 14 films and 42 media files. Westminster, Brooklyn Bridge, and the Colosseum are the first three Shorts in that order. Anonymous readback verified all six new objects against the media manifest, and each MP4 supported HTTP 206 range reads. The original import and verification follow.

Source `Assets/catalog.json` was imported once through `supabase/seed.sql`: 2 editorial publishers without Auth identities, 11 clips, 12 places and 12 guides. Every ID and source field, including nested guide sections, was compared through the same authenticated snapshot used by the app. Source object-key ordering was normalized for JSON object comparison; arrays preserve order. The Iceland waterfall clip deliberately has no specific place association because its source does not identify the waterfall.

All 36 business media files were uploaded through the official logged-in Supabase dashboard: 11 MP4 files, 11 JPEG covers and 14 destination photographs. `media-verification.json` records successful no-credential public GET, actual MIME, complete byte length and SHA-256 for every manifest entry. Every byte/hash matches `Assets/media-manifest.json`; no broken object references or local media fallback remains. The largest initial object is below 9 MB.

`catalog` and `legal` are deliberately public and maintenance-write only. `uploads` is private: the owner's UUID scopes writes; authorized conversation membership scopes attachment reads; referenced profile avatars are discoverable to signed-in members. Signed URL expiration is one hour in the app and must be resolved again on a subsequent request. The Free plan has a 50 MB global object ceiling, so video upload is capped at 50 MB and photos at 5 MB. The bucket-limit followup source is `20261103100000_free_storage_limit.sql`; the coordinator records its application separately.

## Finite verification

These are isolated backend API checks, not application runtime acceptance. Three fresh, independent Auth identities were used; no credentials are shipped and no production user was used. Tests did not perform payment or contact an external backend.

| Scope | Actual evidence |
| --- | --- |
| Auth/entry | Real anonymous signup, persistent token identity, authenticated bootstrap; raw unauthenticated RPC and invalid-token entry denied. |
| New account | Initial zero balance and empty personal likes, journeys and messages; public catalog readable under ordinary authenticated permissions after import. |
| Catalog | All 11/12/12 records and each source field match, and 2 editorial publishers remain distinct from real member accounts. |
| Profile and relationships | Partial profile writes preserve omitted fields; actual follows persist in both directions; server uses trusted user IDs. |
| Likes/saves/comments | Clip like/save, place save, public comment/reply, own deletion, other-member deletion denial, report and withdrawal persisted and were read back. |
| Journeys | Save/readback/delete succeeded; another identity could neither read nor overwrite the private journey. |
| Chat | Canonical direct pair deduplicates; stable client message ID deduplicates; one non-mutual greeting, mutual-follow messages, group messages, partial preferences and blocking behave authoritatively. Nonmember history/write access was denied. |
| Realtime | Both participant sockets received actual persisted messages in both directions. Disconnect/rejoin recovered intervening history and resumed live events; the nonmember received no message event. Streams/connections closed after checks. |
| Media/submissions | Real JPEG and MP4 upload; owner read; unshared and nonmember signing denied; participant signed attachment GET matched bytes; avatar visibility worked; private pending submission saved/read/deleted. |

Detailed results are in `api-verification.json`, `catalog-verification.json`, `realtime-verification.json`, `media-verification.json` and `schema-verification.json`. The first IM probe waited only for `phx_join` acknowledgement and timed out before PostgreSQL readiness. The corrected bounded probe waited for the `system` ready event and passed; `TravelStore` also refreshes on system readiness and every rejoin to close this catch-up window.

Security advisors were reviewed after deployment. Guest-policy and authenticated-definer warnings reflect the chosen guest/API design; leaked-password protection is not enabled for the unused password flow. Actual privileges and scope checks are documented in `security-review.md`. These acknowledged warnings do not assert a formal security certification.

## Agreements

The [November 10 Lulu revision](legal/2026-11-09-lulu/README.md) updates the operator and contact email. The bundled PDFs, expected checksums, and consent identifier now use the revision. The same public URLs serve the November 9 files until the Storage objects are overwritten. [Public verification](legal/2026-11-09-lulu/public-verification.json) records the previous publication.

### Original November 3 publication

The source Markdown and rendered, searchable, embedded-font PDFs are in `docs/backend/legal/`. Both final PDFs have two pages; rendered pages were visually checked and public-download text was extracted. Neither brand/operator/contact nor a staffed support address was invented. Current private development status and public-release identity dependencies are stated accurately.

- Terms: `https://dlbaneeshycwmhgfeokx.supabase.co/storage/v1/object/public/legal/terms.pdf` — HTTP 200, `application/pdf`, 36,876 bytes, SHA-256 `b4f353127f392497f7066116e15122fa45115f5f3f70ab4c03cba60c8872c921`.
- Privacy: `https://dlbaneeshycwmhgfeokx.supabase.co/storage/v1/object/public/legal/privacy.pdf` — HTTP 200, `application/pdf`, 37,399 bytes, SHA-256 `70d20bc04f03aed49539e3913d9d29be4efb7076a3f4688cf291c524a5f8059a`.
- Consent identifier: `travel-9d874d451884299ab284b3a3`, derived from the final two PDF byte sequences by the coordinator.
- The agreement pair and public links are now complete and frozen. Subsequent stage B work or generic optimization does not authorize changing their source, bytes, version, public object or links; only an explicit owner request does.

## Cleanup and remaining deployment approval

The two isolated test upload objects and the dashboard-generated empty-folder marker were removed through the official Storage dashboard. The three Auth identities used only for this deployment verification were `935137a5-2ec9-4c08-94f0-1b3b335a862d`, `8ad4a688-8256-43ff-b5f9-2ade03bb0e27` and `9c17b235-52f0-4d39-8f36-38d5bae7bee7`.

An initial attempt to open their deletion was rejected by automatic approval review. Work stopped until the owner explicitly approved cleanup of these three test accounts. The subsequent official Auth dashboard deletion targeted only those UUIDs. Two were removed in the first batch; one mutual-follow FK required retry after the other two had been removed. The final UI displayed no project users and a successful deletion toast. No unrelated account was touched. The coordinator then deleted only the two recorded empty test conversations with a no-member predicate. Final SQL evidence confirmed no fixture Auth users or conversations remain, no messages/journeys/submissions remain, and the private uploads bucket is empty. The 2 editorial publishers, 12 places, 11 clips, 12 guides, 36 catalog objects and 2 legal objects are preserved. All 18 application tables retain RLS; raw anon action execution remains denied. Temporary test tokens were removed from local `/tmp` after checks. This one-time fixture approval does not authorize a persistent account-deletion endpoint.

Separately, the `travel-account` Edge deployment was rejected by automatic approval review because it creates a persistent privileged account-deletion capability. The source is reviewable at `supabase/functions/travel-account/index.ts`, but the function is not deployed and in-app account deletion is not currently available. The user has not approved that deployment, and it has not been retried. These are two separate approvals.

Release also requires the owned registered Bundle ID/team, APNs signing/capability configuration and actual push delivery infrastructure. Apple checkout remains gated on verification configuration and storefront availability. The hosted coin and guide APIs are recorded in [Coins and paid guides](coins-and-guides.md). External authentication, Socket forwarding and stage B remain unrequested. No app build, typecheck, Preview, app launch, simulator or runtime tests were performed.

## Public profile statistics

Migration `20261110030651_lulu_public_profile_statistics` provides the authenticated `travel_profile_stats` RPC and its private aggregate helper. It returns received short-video likes and saves plus following and follower counts, without returning private collection rows. The public wrapper uses invoker security; the non-exposed helper has a fixed empty search path and requires an authenticated profile. Anonymous execution is revoked. No member data or engagement rows were created or changed.

Read-only verification under the authenticated role returned real counts for both editorial profiles. Privilege checks confirmed anonymous execution denied, authenticated execution granted, and the public wrapper is not a security definer. The client checks the returned profile ID and nonnegative integer counts. App compilation, typechecking and simulator acceptance remain unperformed.

## Editorial portraits and display baselines — November 10

Migration `20261110034510_lulu_editorial_portraits_and_display_counts` is deployed. The two existing editorial profiles now reference inspected 512-pixel Pexels portrait photographs. `Assets/editorial-portraits.json` records sources, credits, licenses, hashes and inspection. These two exact HTTPS CDN references are allowlisted by the media resolver; they are not Supabase-hosted or bundled. All other catalog/legal/private-upload routing is unchanged. Portraits illustrate editorial publishers and do not establish the subjects' nationality, membership or endorsement.

The owner explicitly authorized modest illustrative display statistics. A private, client-inaccessible table stores fixed 10–20 baselines for the two editorial profiles, 14 existing videos and 12 existing guides. Real like/follow/save rows are unchanged. Profile RPC results include actual aggregates and illustrative baselines separately, with display totals. Video counts combine the fixed baseline and actual likes. Guide cards currently display only the authorized editorial baseline: there is no guide-like action, and saves/purchases are never relabeled as likes. Real member profiles have no baseline. Media credits disclose the editorial presentation.

The authenticated `travel_content_stats` invoker wrapper calls a non-exposed, fixed-search-path aggregate helper with an authenticated-profile check. It returns counts only, excludes blocked publishers, and never returns liker identities or paid guide bodies. Client counts refresh with the snapshot, use a dash on failure, and clear on sign-out. The public profile's guide grid retains white padding but has no button underneath; its image carries the location and red-heart count at the lower left. Short-video tiles retain edge-to-edge photos with the same count overlay. The paid badge and exact-offer payment gate remain in place.

Verification: read-only authenticated queries returned Europe 17/12/14/18 and North America 13/17/11/16 for Likes/Saves/Following/Followers. Europe includes one existing real like above its 16 baseline. All 14 video and 12 guide counts were 10–20 at verification. Member display counts equaled actual aggregates, member baselines were empty, and repeat reads were stable. Counts of actual likes (1), follows (0) and profiles (3) were unchanged. Anonymous aggregate execution and direct authenticated baseline-table access were denied; authenticated aggregate execution was granted. Advisors reported the intentional default-deny private baseline table as RLS-without-policy INFO, alongside pre-existing project warnings. No relaxation was made.

The six changed Swift files passed syntax parsing, and whitespace/JSON checks passed. These are static checks and bounded database reads, not compilation, typechecking, device/UI acceptance or Apple payment tests. Those runtime checks remain unperformed.

### Account deletion with community retention

The owner requested deletion of personal data and retention of already-published community videos and guides. The local implementation validates the caller with Supabase Auth and accepts a delete action without a caller-supplied account ID. Its service-only preparation step pauses uploads for that account, including uploads attempted with stale tokens after the identity is removed. It copies referenced published video and cover objects to protected community paths and verifies the copies before committing new clip paths. The storage API then removes personal uploads before the Auth admin call. A retry reuses staged copies and can finish remaining cleanup. Published media pointers are usable even if a later phase fails.

The database transaction detaches the deleted profile and account byline from published clips and guides. It keeps their identifiers, published bodies, video files, public source links, prices, and other members’ saved clips and guide entitlements. The transaction removes unpublished guide bodies and cascades private account records, including submissions, journeys, messages authored by the account and wallet activity. It preserves other participants’ messages. The Apple delivery deduplication ledger retains its transaction key with no account owner, preventing a deleted account’s transactions from being credited again. Supabase describes the Storage prerequisite and the lifetime of outstanding access tokens in [User Management](https://supabase.com/docs/guides/auth/managing-user-data#deleting-users).

The SQL migration and the revised Edge Function are prepared locally. The live deployment gate in BackendConfig.json remains false. The earlier automatic review rejection concerned deploying a persistent privileged deletion endpoint. Obtain explicit owner authorization for this migration and function before live deployment. After deployment, verify the endpoint with disposable accounts, including Storage object bytes, a purchased guide entitlement, private data removal, retry and third-party isolation, before setting the app flag to true.

Local evidence consists of the Node handler regression suite and an isolated PostgreSQL migration and RLS scenario. The PostgreSQL scenario models Storage API copies and removals with fixture metadata. It does not establish Supabase-hosted Storage or Auth behavior. Swift sources were parsed without building or running Lulu.
