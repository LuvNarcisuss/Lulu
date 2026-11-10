# Lulu local StoreKit verification

## Current mode

The owner selected local Xcode StoreKit testing on November 10, 2026. The single Lulu scheme runs Debug with `Configuration/LuluCoins.storekit` and `LULU_LOCAL_STOREKIT=1`. Debug uses `im.seex.sao2` and Yu Sun team `JPTS6M4T5B`; Release retains `com.lulu.travel`. Selecting Apple-backed testing requires both StoreKit Configuration = None and removal of the local-wallet environment variable in the same scheme.

`LocalStoreKitWallet` is compiled only in Debug. It accepts only StoreKit-verified Xcode-environment consumable transactions for the signed account token, known product, quantity one and no revocation. It writes an account-scoped atomic file before finishing the transaction and retains all transaction identifiers for deduplication. The wallet shows a distinct local-test balance and history. It never writes Supabase wallet rows or grants production guide entitlements. The November 10 guide checkout fix adds isolated local debits and persisted access to project-owned editorial guide copies, compiled only in Debug. Ordinary app authentication remains required; test code does not add a production login bypass.

Production delivery still uses the original server verifier and authoritative ledger. Apple sandbox/production catalog access, numeric Apple ID, production signing and production purchase acceptance remain separate prerequisites. The local configuration does not register products with Apple.

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
