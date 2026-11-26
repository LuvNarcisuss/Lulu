# Travel Application Implementation Plan

> **For agentic workers:** Use independent domain work under superpowers:dispatching-parallel-agents, then integrate and review the complete application. Owner instructions prohibit compilation and runtime tests.

**Goal:** Deliver the unnamed five-tab travel iPhone application with real assets and a dedicated Supabase stage A backend.

**Architecture:** UIKit feature controllers share a MainActor TravelStore. Records use a small Codable JSON representation. Auth, business state and realtime synchronization are isolated behind the store; feature screens never manufacture business success.

**Tech Stack:** iOS 16+, Swift 5, UIKit, AVFoundation, MapKit, PhotosUI, StoreKit, Supabase Swift.

**Spec:** docs/superpowers/specs/2026-11-03-travel-app.md

## Global Constraints

- English project artifacts; Chinese owner-facing communication.
- iPhone only, portrait, iOS 16+, Swift 5, UIKit.
- No compilation, typechecking, app/simulator launch, Preview or runtime tests without explicit authorization.
- Generated raster icons/backgrounds and licensed custom fonts; real inspected travel footage and photography.
- Independent Supabase project in the owner-selected 139 organization; stage A only.
- No inherited identity, SKUs or private data; no fake online/payment success.

## Review Focus

- Late media callbacks must not revive playback after leaving a screen.
- Failed writes must preserve draft input and the prior committed state.
- A nonmember must not read private conversations, itineraries, attachments or wallet records.
- Catalog and media counts must agree, including every cover-to-video mapping.
- Missing app name, signing identity or SKUs must remain explicit configuration dependencies.

### Task 1: Shared shell and contracts

Files: AGENTS.md, TravelApp/project.yml, TravelApp/Sources/Core, TravelApp/Sources/Design, docs/tasks/interfaces.md.
- [x] Define Record/JSONValue and the exact store/UI boundary.
- [x] Build welcome, consent, navigation and generated-asset design primitives.
- [x] Generate and statically inspect iPhone-only Xcode metadata.

### Task 2: Independent content and visual assets

Files: Assets/, TravelApp/Resources/, docs/media/, scripts/media*.
- [x] Source and inspect distinct real clips and photographs; author destination/guide catalog from primary travel sources.
- [x] Generate icon sheets and backgrounds with the image model; package licensed fonts.
- [x] Record hashes, license/source evidence and media-to-destination mappings.

### Task 3: Independent Supabase backend and store

Files: supabase/, TravelApp/Sources/Backend/, docs/backend/.
- [x] Record one creation attempt and provision one project in the selected organization; reconcile unknown results before retrying.
- [x] Deploy RLS schema, authoritative actions, guest bootstrap, private user uploads and realtime messaging.
- [x] Implement TravelStore against the contract and actual session identity, with refresh/reconnect and meaningful failures.
- [x] Import complete content/media, publish PDF agreements and perform finite isolated API/permission checks.

### Task 4: Independent social and wallet screens

Files: TravelApp/Sources/Features/Social/, TravelApp/Sources/Features/Profile/.
- [x] Implement chat, actual member search/groups, drafts/filters/preferences, attachments and report/block.
- [x] Implement own/public profile, edits, collections, wallet/history and settings.
- [x] Keep unconfigured IAP unavailable and actual RTC absence visible; inspect persistence/error paths statically.

### Task 5: Discovery and planning

Files: TravelApp/Sources/Features/Shorts/, Explore/, Journeys/.
- [x] Implement paged AVPlayer feed, interactions, comments/replies and safe upload.
- [x] Implement map/list discovery, sourced guide details, place saves and itinerary connections.
- [x] Implement private journey creation, daily stops, checklist, budget, notes and atomic saves.

### Task 6: Integration and evidence

Files: scripts/static_audit.py, README.md, docs/verification.md.
- [x] Reconcile routes, assets, API actions, declarations and project resources.
- [x] Run static checks and bounded backend validation; inspect representative media and generated artwork.
- [x] Perform an independent source review; repair material findings and record verification limits.
- [x] Deliver actual project path, deployed project details, pending identity/IAP fields and unperformed runtime checks.

## Execution disposition

All listed source, asset, metadata, integration and permitted static/API work has been carried out. This does not imply app runtime acceptance or complete stage-A release acceptance. App compilation/typechecking/runtime were expressly unperformed. The persistent self-account deletion endpoint remains undeployed after automatic review requested explicit destructive-effect authorization. App identity, owned IAP configuration/verified delivery, APNs signing and legal operator details remain external release dependencies. The owner separately approved temporary verification-account cleanup, and only that scoped cleanup was executed. See docs/verification.md for evidence and limits. The [November 26 company deployment](../../backend/integration.md#account-deletion-with-community-retention) supersedes this historical deletion status.
