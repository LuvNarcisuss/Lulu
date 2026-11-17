# Lulu local StoreKit verification

## Current mode — November 17, 2026

Debug and Release retain the owner-selected test settings, `im.seex.sao2` and Yu Sun (`JPTS6M4T5B`). Restore `com.lulu.tourtravel` with Team None when the owner requests the switch. Ordinary Run queries Apple's catalog with no `.storekit` selection or `LULU_LOCAL_STOREKIT` launch variable. Production retains `com.lulu.tourtravel`, Apple ID `6832914128`. Hosted version 4 additionally accepts `im.seex.sao2` in Sandbox only. The current 400-coin test product is `neiku_30`; the remaining eight identifiers are unchanged.

Local StoreKit remains available through the isolated `LuluPurchaseTests` test target, which explicitly loads the nine-product fixture. To test the local wallet from the app UI, use a Debug simulator build, select `LuluCoins.storekit` for that run, and set `LULU_LOCAL_STOREKIT=1`. Local balances remain account-scoped and separate from hosted wallets.

Apple sandbox uses separate server balances, delivery records and editorial-guide entitlements. Production and sandbox transactions require Apple verification, matching environment, Bundle ID, product and quantity, plus account-token checks when that field is available in the selected receipt contract. Xcode transactions are never submitted for hosted credit. Sandbox funds cannot purchase real members' paid guides.

The opt-in `LuluAppleSandboxUITests` target requires `LULU_SANDBOX_UI_TESTS=1`, checks that the wallet reports Sandbox before buying, and uses native Apple confirmation. Credentials and side-button confirmation remain owner actions. It must never be treated as a production purchase test.

## November 17 removal of the API-key checkout dependency

The owner correctly identified that consumable receipt verification need not use
an App Store Server API signing key. The earlier StoreKit 1 implementation submitted
only a transaction ID and required `.p8` lookup credentials before allowing checkout.
That design caused the observed `apple_iap_configuration` rejection even though
Apple returned the `neiku_30` product.

Version 4 is deployed with `status_receipt` and `deliver_receipt`. The current client
submits its app receipt after a purchased callback. The server verifies it with
Apple before invoking the same atomic credit RPCs. Production-first verification
and the `21007` sandbox retry handle App Review without trusting the client hint.
Exact Bundle ID/product checks, quantity, refund rejection and transaction ownership
remain enforced. Legacy receipt account-token limitations are documented in
[Coins and paid guides](coins-and-guides.md). No new database privileges or balances
were changed and no private key was uploaded.

The missing-key readiness regression failed before this fix and passed afterward.
The receipt verifier, HTTP handler and retained transaction-ID compatibility tests
report 81 passing cases. The isolated PostgreSQL harness passed duplicate-credit
and cross-account/bundle isolation checks. Deno type checking passed, and hosted
version 4 readback matched all four source files exactly. These results are not
Apple sandbox payment acceptance.

The updated receipt client built successfully on November 17 using the existing
explicit Yu Sun profile. An initial compile failed because the receipt reader
referenced a file-private error type; introducing its own private error type
resolved that failure, and the subsequent build exited successfully. The artifact
passed strict code-signature validation and retained `im.seex.sao2` and `neiku_30`.
At 11:27 China Standard Time, `devicectl` confirmed installation and launch on the
designated iPhone. Evidence uses `/private/tmp/LuluStoreKit1-receipt-` prefixes.
No UI automation success is claimed: the prior XCTest driver failure remains.
Before the owner's purchase attempt, read-only hosted inspection showed no sandbox
delivery rows and zero production deliveries.

### Owner-confirmed sandbox wallet delivery

On November 17, the owner confirmed successful credit after being asked to purchase
the 400-coin `neiku_30` package in the actual Wallet on the designated iPhone. This
is owner-observed Apple sandbox acceptance for the first tier with `im.seex.sao2`,
Yu Sun and the receipt-based StoreKit 1 build. It is not an isolated local ledger
result or an automated UI assertion. The owner did not provide a new balance
screenshot or transaction identifier with this confirmation.

Two follow-up read-only database checks failed at the connector transport layer;
neither returned database rows. Independent post-purchase ledger inspection is
therefore not claimed. The other eight Apple products, the formal Bundle ID and
production purchases remain outside this successful first-tier acceptance.
Keep the current test identity until the owner requests a switch.

## November 17 first-tier test package and hosted repair

The owner selected `neiku_30` for the 400-coin tier. Both the bundled catalog and
isolated fixture now request it. The other eight products are unchanged. Hosted
version 3 accepts this product for `im.seex.sao2` in Sandbox and retains the original
mapping for pending transactions. The hosted schema now allows the exact test
bundle in separate sandbox records. The app selects that sandbox wallet even
before a receipt exists. No sandbox account permissions were changed.

The updated source built successfully for the designated iPhone using Yu Sun's
explicit `im.seex.sao2` profile. The artifact passed strict code-signature validation;
its bundled catalog identifies `neiku_30` as 400 coins. `devicectl` confirmed
installation and launch of `im.seex.sao2`. Build, installation and launch evidence
uses the `/private/tmp/LuluStoreKit1-neiku30-` prefix.

Two attempts to execute `AppleSandboxUITests.testFirstSandboxPackage` both failed
before XCTest established its driver connection: the runner exited with code 74.
Neither attempt reached Wallet, requested a purchase, or asserted the balance.
The result bundles are `LuluStoreKit1-neiku30-wallet-01.xcresult` and
`LuluStoreKit1-neiku30-wallet-02.xcresult` under `/private/tmp`. These are failed
acceptance attempts, not successful StoreKit tests. Device Wallet diagnostics
have been requested from the owner. Apple catalog availability, test-key readiness,
Apple account permissions and purchase-to-wallet delivery remain unverified.

### Owner-provided device diagnostics after installation

The owner supplied diagnostics from the installed test app on November 17:
`im.seex.sao2`, version `1.0.0`, hosted Sandbox, local StoreKit wallet disabled,
and device payments allowed. Apple returned `neiku_30` and marked the other eight
requested identifiers invalid. This verifies catalog retrieval for the first test
tier only; it does not verify a purchase or establish why the other products are
invalid in this storefront/application context.

Delivery readiness was false with `apple_iap_configuration`. Version 3 returns
this code when the test app's issuer ID, key ID or P-256 PKCS #8 private key is
missing or fails local parsing/import. This response does not test whether Apple
accepts the key or whether a sandbox tester has permission. The owner then supplied
a screenshot of Lulu's own unavailable notice after tapping the 400-coin package.
The client readiness gate blocks checkout before adding a payment to StoreKit.
The next dependency is the In-App Purchase key for the team owning `im.seex.sao2`,
configured as `APPLE_TEST_IAP_ISSUER_ID`, `APPLE_TEST_IAP_KEY_ID`, and
`APPLE_TEST_IAP_PRIVATE_KEY`. The owner has been asked for the existing key's local
path and identifiers; private key contents must remain outside project artifacts.
No completed Apple transaction or credited wallet balance has been observed.

## November 17 StoreKit 1 iPhone verification

### Signing configuration correction

The later signing inspection found that XcodeGen 2.45.4 serialized the target's
`SystemCapabilities` dictionary as a quoted Swift dictionary description. The
project also lacked an explicit StoreKit framework dependency. Xcode did not show
In-App Purchase in Signing & Capabilities. This is a configuration defect, not
proof that it caused the reported Apple account-permission rejection.

`project.yml` now links `StoreKit.framework` and invokes
`scripts/normalize_iap_capability.py` after generation. The narrow normalization
preserves all other project values, rejects unknown malformed capability content,
and leaves a correct dictionary unchanged. The check failed against the original
project and passed after regeneration. Regenerating again retained the correction.
Xcode's Signing & Capabilities panel visibly showed In-App Purchase afterward.
See the [upstream serialization issue](https://github.com/yonaskolb/XcodeGen/issues/1637)
and [XcodeGen capability guidance](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/FAQ.md#how-do-i-add-an-xcode-capability).

Xcode's selected profile was `iOS Team Provisioning Profile: im.seex.sao2`, created
November 6, 2026, expiring November 6, 2027. Its profile details confirmed the
matching explicit App ID, Yu Sun team, development certificate, In-App Purchase
capability, and inclusion of the designated iPhone. Debug and Release remain
`im.seex.sao2` with `JPTS6M4T5B`.

No cached profile with the explicit `com.lulu.tourtravel` App ID was found in either
local provisioning-profile directory. The November 16 wildcard-profile evidence
still applies only to that earlier build. The owner's pasted diagnostic identifies
`com.lulu.tourtravel`, while all three current local device build artifacts identify
`im.seex.sao2`. Device enumeration connected successfully but returned an empty app
list, so it did not establish which artifact produced the reported popup.

This correction was checked through project parsing, repeated metadata generation,
and Xcode profile inspection. No new app build, installation, Apple purchase, or
balance delivery was performed during the signing correction. The local XCTest
results below predate this correction. This earlier limitation was superseded by the November 17 exact test-bundle allowlist. Hosted sandbox acceptance can now use `im.seex.sao2` with its owning team's Apple catalog, sandbox account and In-App Purchase API credentials.

### Post-correction device build and local test run

The owner authorized rebuilding, installing and testing again with `im.seex.sao2`
and Yu Sun on the designated iPhone. On November 17 at 10:40–10:42 local time,
`xcodebuild build-for-testing` succeeded from the corrected working tree. The
build retained `ENABLE_DEBUG_DYLIB=NO` and `DEBUG_INFORMATION_FORMAT=dwarf` from
the earlier working device test configuration. No source or test assertions were
changed for this rerun.

The newly built `TravelApp.app` passed `codesign --verify --deep --strict`. Its
Info.plist Bundle ID was `im.seex.sao2`, and both its signature and embedded
profile used `JPTS6M4T5B.im.seex.sao2`. The explicit development profile included
the designated iPhone. `devicectl device install app` reported a successful
installation of that Bundle ID. A subsequent app-list query still returned an
empty list, so installation evidence comes from the successful installer response
and the XCTest host actually running on the required device.

| Run | Observed result |
| --- | --- |
| `LuluStoreKit1-SigningFix-20261117-01.xcresult` | Eight passed and one failed. The first catalog request in `testFailedPaymentDoesNotCredit` returned no products, so that case failed before placing a payment. The nine-product credit test passed. |
| `LuluStoreKit1-SigningFix-20261117-02.xcresult` | The focused failed-payment case passed on the same build. |
| `LuluStoreKit1-SigningFix-20261117-03.xcresult` | All nine cases passed, with zero failures or skips. |

The final xcresult identifies the designated iPhone 12, device ID
`00008101-0019755A3690001E`, iOS 27.2.1 (24B156). The nine-tier test asserted a
172,400-coin total across nine persisted entries, reloaded the isolated ledger
after each delivery, and rejected duplicate credit. Failed payments did not
credit, and account isolation and guide spending checks passed. The initial
empty product response remains an unresolved intermittent fixture/startup issue;
the passing reruns do not establish that it has been fixed.

Build log, installation JSON and result bundles are under `/private/tmp`, with
the prefix `LuluStoreKit1-SigningFix-20261117`. The current signed app is at
`/private/tmp/LuluStoreKit1-YXS-20261117-DerivedData/Build/Products/Debug-iphoneos/TravelApp.app`.
Tests loaded `LuluCoins.storekit` through SKTestSession and used StoreKit 1 APIs.
They credited disposable local test ledgers, not the signed-in wallet UI or
hosted balances. Native purchase dialogs were disabled. This run does not verify
the reported Apple sandbox account-permission popup, hosted transaction delivery,
or the wallet UI's balance after purchase. Test and formal Bundle IDs were not
switched, and no sandbox account permissions were modified.

### Earlier local XCTest result

The current source built with Xcode 26.0.1 using `im.seex.sao2` and Apple Development signing for Yu Sun (`JPTS6M4T5B`). The signed XCTest host launched on the owner-selected iPhone 12 running iOS 27.2.1 (24B156). All nine `LuluPurchaseTests` cases passed, with zero failures or skips, in the final result bundle `/private/tmp/LuluStoreKit1-YXS-20261117-04.xcresult`.

The nine-tier test loaded the local fixture through `SKProductsRequest` and placed each purchase through `SKPaymentQueue`. Each credit persisted after reopening its isolated local ledger. Re-delivery preserved the exact balance, and each successfully credited transaction left the queue. The final balance was 172,400 coins across nine entries. The failure case left its separate test wallet at zero.

The first run failed to load the XCTest bundle. A fresh build-for-testing with the debug dylib disabled loaded the bundle. Its first catalog request in the failure case returned no products. The focused rerun and final full run both passed that case. The tests exercised the isolated local ledger through XCTest. The wallet UI and Apple's hosted purchase environments were outside this run.

## November 17 earlier simulator verification

This evidence predates the switch to StoreKit 1 for all client and local test paths. The earlier source built and ran as the XCTest host on the isolated iPhone 17 Pro simulator `Lulu StoreKit QA 20261117`, iOS 26.0.1. The project selected `im.seex.sao2` with Yu Sun (`JPTS6M4T5B`). The simulator binary used ad-hoc signing and its embedded Bundle ID was verified.

All 10 tests passed. The StoreKit 1 case requested an offer, completed a 400-coin test purchase, read the signed transaction, persisted the local credit once and observed the transaction leave the queue. The nine-tier fixture test credited a total of 172,400 local coins using the StoreKit 2 test APIs. Additional cases covered cancellation, account isolation, balance persistence, guide spending and the confirmed sandbox ledger taking precedence over an earlier production installation lookup.

The result bundle is `/private/tmp/LuluStoreKitQA-20261117-03.xcresult`. This run used the local fixture. Apple sandbox delivery and production payment for the corrected build remain pending.

The [November 16 repair evidence](../runtime-acceptance/2026-11-16-1030-purchase-repair/README.md) predates the StoreKit 1 migration. The following sections record historical November 10 evidence.

## Executed verification

Current source was built, installed and launched as the XCTest host on a newly created isolated iPhone 17 Pro simulator named Lulu Purchase QA 20261110, UDID `C28012C2-E393-4313-B34A-5F6C48C67DEF`, iOS 26.0.1 (23A8464), x86_64. Simulator signing used the ad-hoc `-` override; this does not establish physical-device provisioning. The owner's existing Lulu UI Acceptance simulator and its accounts were not reset.

The final xcodebuild command exited 0 and the result bundle reports **3 passed, 0 failed, 0 skipped**:

| Test | Observed result |
| --- | --- |
| `testNineProductsCreditOnceAndPersist` | All nine consumables returned; every numeric price matched the fixture. Nine StoreKit purchases credited 172,400 local coins in total. Re-delivering each transaction did not increase the balance. Reopening the on-disk ledger after each purchase preserved the balance; final history contained exactly nine entries. |
| `testCancellationDoesNotCredit` | Injected StoreKit cancellation returned userCancelled and left the ledger at zero. |
| `testWrongAccountCannotReceivePurchase` | A mismatched account token was rejected without credit; the matching account received exactly the purchased quantity. |

Tests used temporary account UUIDs and temporary ledger directories, paired with a fresh SKTestSession transaction history. Test teardown removed only these temporary ledger files and isolated StoreKit transactions. No Supabase accounts, production coins or real payments were created.

Native payment dialogs were disabled for callback verification. The tests exercised Product.purchase and the same local-delivery class used by the wallet; they did not automate the WalletController buttons, app confirmation cancellation, native-sheet appearance/dismissal, app-process relaunch or deferred approval. Persistence evidence is an independent ledger-instance reload from disk, not a full app relaunch. Those UI/recovery cases remain unverified. StoreKit logged a missing-updates-listener warning in the isolated test harness; normal app purchases retain the adapter's Transaction.updates listener.

The first build attempt stalled during a GitHub dependency update and was stopped before tests. The second reached compilation and exposed an over-complex diagnostic-string expression; splitting it fixed the compiler failure. The third run passed. Existing exact-version dependency checkouts were copied to a separate temporary package cache to avoid changing the owner's cached workspaces.

## Evidence and reproduction

- Durable summary: `evidence/local-storekit-2026-11-10/summary.json`.
- Per-case log: `evidence/local-storekit-2026-11-10/test-results.txt`.
- Full result: `/private/tmp/LuluPurchaseRun-20261110-03.xcresult`.
- Full build/test log: `/private/tmp/LuluPurchaseRun-20261110-03.log`.
- Derived data: `/private/tmp/LuluPurchaseDerivedData`.

The current Lulu scheme contains the LuluPurchaseTests target. Run only that target on an isolated iPhone simulator for a repeat. The fixture is copied into the test bundle, not the app resource phase. Never clear transaction history without isolating or resetting its corresponding local ledger. Ordinary Run from the Lulu scheme now uses local StoreKit automatically; running an older installed app does not apply these code/scheme changes.

## Guide checkout correction — November 10, 2026

The wallet displayed local Xcode credits, while the guide UI compared only the production server balance and routed users to the wallet. The local ledger previously had no spending operation. Guide checkout and the Me wallet summary now use PaymentCatalogAdapter.walletBalance, matching the wallet screen.

Every locked guide opens a price-and-balance confirmation. After confirmation, the adapter refreshes the offer and checks the account, current price and balance. Sufficient funds commit the debit and entitlement before navigation. Only an insufficient-funds result presents Insufficient coins with a Buy coins action. Unavailable balances, changed prices and network failures are not treated as insufficient funds. Map/list, saved cards, author works and in-detail unlock actions share this entry path. An existing entitlement never charges again.

For local Xcode mode, the account-scoped JSON ledger stores credits and guide purchases together with atomic writes. Existing credit-only files decode without resetting their balances. Repeat guide unlocks and repeat StoreKit deliveries do not duplicate credit or debit. Wallet history includes negative guide entries. LocalGuideFixtures embeds exact copies of the twelve project-owned editorial records from Assets/catalog.json inside a DEBUG compilation guard. Only a published, authorless offer with matching guide/place IDs can use those copies after a persisted local entitlement. A member-authored guide without local test content is rejected without a debit; local test coins cannot purchase another user's production content. Production continues to use travel_unlock_guide and server-enforced entitlements, with a separate balance.

Added regression cases cover a verified 400-coin purchase, a 180-coin debit, duplicate access, ledger reload, exact remaining-balance spending, insufficient funds, account isolation, transaction re-delivery, legacy file decoding and rejection of missing guide content. These new cases have NOT been executed. The earlier three-test result above predates this fix and does not validate it. Current checks are source/diff inspection, fixture/source equality and DEBUG-guard inspection only; no compilation, typechecking or app/runtime acceptance was performed for this correction.

## November 10 follow-up

All six local StoreKit tests passed on Lulu Purchase QA 20261110. The later run and the separate wallet UI results are documented in [the social, payments and interface copy verification](../runtime-acceptance/2026-11-10-1531-social-purchases-copy/README.md).
