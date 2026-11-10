# Lulu functional acceptance

The November 10, 2026 interactive run used Xcode 26.0.1 and Lulu UI Acceptance, an iPhone 17 Pro simulator on iOS 26.0.1. The checkout was at d44e421 with pre-existing working-tree changes. The Lulu scheme built the current checkout for simulator execution. The final locally signed app used bundle ID `com.lulu.travel` and was installed and launched on the named simulator.

## Confirmed repairs

- Journey date edits match saved days by calendar date. Dates that remain in range keep their IDs, notes, and stops. Adding dates creates empty records, and removing dates with saved content requires confirmation, including range changes that keep the same total number of days.
- The journey editor provides a Done keyboard action for text fields and notes. The test used it to reach Save, wrote an isolated journey, recovered it after relaunch, and removed it. A read-only backend check returned zero rows for the exact fixture title afterward.
- Chats shows distinct empty states for search, unread, pinned, drafts, and archived views. The archive action names its destination, and choice controls announce the selected state.

## Coverage

| Surface | Observed outcome | Uncovered scenarios |
| --- | --- | --- |
| Welcome and entry | Declining consent preserved the unchecked state. Both current public PDFs opened in-app. Real one-tap entry and re-entry after cold launch opened Shorts. | Offline entry and cross-device session behavior. |
| Shorts | Recorded video advanced, paused, and resumed. Search and the video creation form opened. | Playback lifecycle and rotation, full upload and moderation, persistent engagement and safety writes. |
| Explore | Map, destination list, and filters opened. A locked paid guide showed price, zero balance, and Get coins. Cancel returned to Explore without charging. | Successful paid unlock, author submission and moderation, and device Maps handoff. |
| Journeys | Empty-name validation, keyboard dismissal, actual save, relaunch readback, and cleanup passed. Six focused date logic checks passed after a reproducible failure on the previous implementation. | Full day, stop, checklist, and journal permutations in the UI. |
| Chats | Member discovery, invalid new-group input, unread selection and archive control passed. The live project had RLS on all five checked private route tables, three chat tables in the Realtime publication, and authenticated-only action execution. | Two-device direct or group message delivery, private attachments, reconnect behavior, and access revocation. |
| Me and wallet | Profile edit opened. The wallet displayed nine tiers and disabled purchase controls after loading ended. | Profile writes, private collections and uploads, purchase delivery, Apple sandbox and production StoreKit, push delivery, and account deletion. |
| Static audit | 249 assertions passed, and both project and app plists validated. | Accessibility sizes, VoiceOver walkthrough, and physical-device testing. |

## Test evidence

Twelve distinct XCTest scenarios passed across the signed baseline and focused reruns. The unsigned initial run lacked a Keychain entitlement, which produced system error -34018. A locally signed simulator build resolved that test-environment issue. The initial chat and journey failures were reproduced and passed after the fixes. The first playback predicate targeted an ambiguous slider query. A visible-slider rerun confirmed progress, pause, and resume.

The test runner used a simulator session and an isolated journey fixture. Account deletion was outside this run. No purchase was submitted.

Local evidence directory: `/private/tmp/lulu-full-acceptance.w02tlKrO`. The directory contains `SignedAcceptance.xcresult`, `ExtendedAcceptance.xcresult`, `FinalAcceptance.xcresult`, `PlaybackAcceptance.xcresult`, the four result summaries, `FinalRegressionBuild.xcresult`, the journey regression logs, the temporary test source, and simulator screenshots.
