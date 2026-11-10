# Lulu social, payments and interface copy verification

November 10, 2026, Asia/Shanghai. The checkout was `/Users/apple/Desktop/Lulu`. The source baseline was `7030c4133002347e80f94d5748f12019df418c3f` with the owner's existing Explore and specification edits. The latest local source was built with `LuluApp/Lulu.xcodeproj`, shared scheme `Lulu`, and locked packages. Debug used `im.seex.sao2` with simulator ad-hoc signing. Release remains `com.lulu.travel`.

The isolated destination was **Lulu Purchase QA 20261110**, iPhone 17 Pro, iOS 26.0.1 (23A8464), UUID `C28012C2-E393-4313-B34A-5F6C48C67DEF`. The build, install and launch succeeded after the interface copy changes. The regular Lulu UI Acceptance simulator was not reset.

| Area | Expected | Actual |
| --- | --- | --- |
| Shorts likes and saves | Toggles persist and appear under Me. Undo removes them. | App UI passed both toggles, collections and undo. Hosted checks passed clip and place saves, deduplication, ownership and removal. |
| Comments | Add, read, reply and delete according to ownership. | App UI passed posting and own deletion on both builds. Hosted checks passed reply, foreign deletion rejection and owner deletion. |
| Direct chat | An isolated peer can be found and messaged. Repeated IDs resolve to one message. Only members can access the thread. | App UI sent to the dedicated QA peer and the exact message was read back from Supabase. Hosted checks passed canonical direct chat, reply, deduplication, greeting limit, read state, draft, pin, mute, archive and blocking. |
| Groups and realtime | Test members see persisted group messages. Two independent connections receive events and recover missed history. An outsider cannot subscribe to the thread's data. | Hosted checks passed group persistence, two WebSocket clients, missed-message catch-up and outsider isolation. |
| Voice and video calls | The unavailable action explains its state without signaling a call. | App UI passed the availability message. There is no calling service or call connection to exercise. |
| Local StoreKit, ledger | Nine test packages credit once, persist, and isolate accounts. Cancellation, incompatible accounts and missing guide content do not change the balance. | Six of six `LuluPurchaseTests` passed. Credits totaled 172,400 test coins. The suite verified 400 credits, a 180-coin debit, 220 remaining, repeat unlock with no second debit, persistence, insufficient funds and legacy compatibility. |
| Local StoreKit, wallet UI | Show test-only confirmation, preserve balance on cancellation, and unlock a 180-coin guide after a 400-coin recharge. | Passed across the native Xcode transaction and latest-build follow-up. App confirmation and native-sheet cancellation left a zero balance. A later native confirmation showed Xcode purchase success. The latest build read the 400-coin balance after launch, opened the paid Rome guide, charged 180 once, showed Payment successful, opened the guide, and showed 220 after another launch. The isolated ledger independently showed one credit, one debit and the same balance. |
| Hosted wallet | A new account starts at zero and cannot debit an unpaid guide. | Confirmed against the Lulu Stage A project `dlbaneeshycwmhgfeokx`. No hosted credit or charge was attempted. |
| Concise interface copy | Remove repetitive guidance and taglines. Preserve labels, meaningful states, prices, consent, legal links and confirmation consequences. | Latest-build UI passed welcome, Journeys empty state, Add a traveler action sheet and Settings. Latest-build comment deletion passed with a title-only sheet and an explicit Remove action. |

The copy sweep covered the welcome screen, all five tabs and their supporting forms and sheets. It kept the recorded media credits and user-authored content. `git diff --check` passed. The real backend checks used three explicitly marked disposable guest identities and a fourth guest on the isolated simulator. The three marked API users and all three test chats were removed after a scoped ownership check. A read-back found zero remaining API users, test chats or API fixture comments. The isolated simulator guest and its local test ledger were retained for inspection. No real members were contacted.

Apple sandbox and production purchases, deferred Apple approval, physical-device acceptance, a new chat photo upload, video calls, and an exhaustive re-run of secondary screens were outside the verified evidence. Earlier navigation coverage is recorded in [the broad acceptance report](../2026-11-10-1154-full-functional.md).

## Evidence

- `backend-results.json` records eight passed hosted check groups.
- `storekit-summary.json` records six passed Xcode StoreKit tests.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/Purchases.xcresult` and `/private/tmp/lulu-deep-qa.iiwD3eCU/SocialUI.xcresult` contain the XCTest results.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/WalletUI.xcresult` contains native sheet and cancellation evidence and the initial failed recharge probe.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/CopyAndGuideUI.xcresult` contains the two passed latest-build UI checks and the separate zero-balance guide attempt.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/copy-build.log` and `/private/tmp/lulu-deep-qa.iiwD3eCU/copy-install-launch.log` record the build, installation and launch.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/CopyAttachments/27284021-8685-4675-A241-0AEDFE4EF40B.png`, `/private/tmp/lulu-deep-qa.iiwD3eCU/CopyAttachments/D0921534-D46A-4B8D-9EC0-A608CEC50F3D.png` and `/private/tmp/lulu-deep-qa.iiwD3eCU/CopyAttachments/FBB49F54-FC81-4CFC-A401-FE5E238F55D2.png` show the latest welcome, Journeys and traveler action sheet.


The initial checkout probe confused the package quantity with the wallet balance. The first guide attempt therefore correctly refused a zero-balance purchase. The native retry reached the Xcode success alert, which the first UI runner had not dismissed. The successful follow-up asserted the explicit wallet entry after restarting and the balance after guide purchase and another restart.

- `/private/tmp/lulu-deep-qa.iiwD3eCU/native-live.png` shows the native Xcode transaction success receipt.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/FinalWalletAndGuideUI.xcresult` contains the passed latest-build wallet and guide flow. `wallet-ui-summary.json` is its machine-readable summary. `wallet-ledger-aggregate.json` contains the independent balance cross-check without user, guide or transaction identifiers.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/final-build.log` and `/private/tmp/lulu-deep-qa.iiwD3eCU/final-install-launch.log` record the final build and deployment to the designated simulator.
- `/private/tmp/lulu-deep-qa.iiwD3eCU/FinalWalletAttachments/9AA22B11-9ECF-445B-8240-652CA0C6DBFE.png`, `/private/tmp/lulu-deep-qa.iiwD3eCU/FinalWalletAttachments/9B8526DD-3E54-4B42-A0B4-86B2904E9F15.png` and `/private/tmp/lulu-deep-qa.iiwD3eCU/FinalWalletAttachments/7791831B-11E3-44C5-AB43-6ABEF12A594B.png` show 400 coins, the guide payment result and the 220-coin balance after relaunch.
