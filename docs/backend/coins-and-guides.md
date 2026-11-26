# Coins and paid guides

The wallet uses StoreKit 1 and nine consumable coin packages. The default Xcode simulator Run loads their prices from the local StoreKit catalog and credits an account-scoped test wallet without contacting a payment service. Apple sandbox and production use the hosted receipt flow below. The production identity is `com.lulu.tourtravel` / `6832914128`. The test identity `im.seex.sao2` has a bundle-scoped Apple sandbox wallet. For the local and Apple sandbox configurations, see [Local StoreKit verification](local-storekit.md).

The hosted StoreKit 1 path calls `status_receipt` before checkout and `deliver_receipt` after a purchased callback. It reads the Base64 app receipt, refreshing a missing receipt with `SKReceiptRefreshRequest`, and submits it with the specific transaction and product IDs. The server sends that receipt to Apple's production `verifyReceipt` endpoint, then to Sandbox only after status `21007`. Consumables require no `.p8` signing key or subscription shared secret in this path. Apple marks `verifyReceipt` deprecated; it remains the selected compatibility path for this StoreKit 1 repair. [Apple receipt validation](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store) and [consumable receipt lifetime](https://developer.apple.com/documentation/appstorereceipts/responsebody/receipt-data.dictionary/in_app-data.dictionary).

Only an Apple status-zero response with the correct endpoint environment, receipt type, bundle, requested transaction, product and quantity can reach the existing atomic ledger. Refunded, revoked and subscription rows are rejected. The server checks Apple's account token when present. Legacy consumable receipts can omit that field: those receipts are treated as purchase credentials, and the authenticated claimant becomes the immutable transaction owner through the existing atomic ledger. This is not an Apple-signed account-token guarantee when the field is absent. The client rejects locally queued purchases carrying another account UUID. A replay by another account cannot receive the same transaction, and repeated delivery cannot increment the balance twice.

The verified Apple environment selects the wallet. The client refreshes its authoritative balance and history after acknowledgment and calls `finishTransaction` only after delivery and refresh succeed. Receipt, network, verification or wallet-read failures preserve the unfinished order. Version 4 adds this flow while retaining the earlier signed-JWS and transaction-ID API contracts for installed older builds; the latter still requires API credentials. Those credentials are not required by the current receipt-based app. No provided private key was uploaded or embedded.

| Reference USD | Coins | Product ID |
| ---: | ---: | --- |
| Apple storefront price | 400 | `neiku_30` (current test); `iltpkpefqtjskxel` (original) |
| 1.99 | 800 | `eweerqrczkwsjyjn` |
| 4.99 | 2,450 | `bfktecvbuyjzwxtp` |
| 9.99 | 5,150 | `zsadvhodvgamjqqp` |
| 19.99 | 10,800 | `qtqrufubdpyvzjzs` |
| 29.99 | 17,000 | `ipcijraguygtcpsa` |
| 49.99 | 29,400 | `azjrhiwubtjsrbzh` |
| 69.99 | 42,700 | `qjcdfljcmzajynnd` |
| 99.99 | 63,700 | `rzeethasxinmprew` |

The two added product IDs belong to the 29.99 and 69.99 tiers. The verifier pins Apple Root CA G3. Sandbox credits and Xcode test credits use separate ledgers.

The catalog uses a 20-second timeout and preserves eligible products in a partial response. Checkout rechecks the account, device restrictions, and verifier before opening Apple's sheet. Debug diagnostics distinguish requested, returned, missing, and Apple-confirmed invalid IDs. See [Local StoreKit verification](local-storekit.md) for the isolated runtime evidence.

## November 17 owner-confirmed first-tier sandbox delivery

After installing the receipt-based StoreKit 1 build on the designated iPhone, the
owner confirmed that the actual Wallet received the purchased 400-coin package.
The successful test used `neiku_30`, `im.seex.sao2` and Yu Sun. It required no `.p8`
key. This acceptance is based on the owner's on-device report; follow-up database
inspection failed because the Supabase connector transport was unavailable.
It does not establish availability of the other eight products or acceptance under
the formal identity or in Production. See [device evidence](local-storekit.md).

## November 17 test identity and first-tier change

The owner confirmed that the nine products were created under `im.seex.sao2`, then selected `neiku_30` as the temporary 400-coin product. The current app catalog and local fixture use that identifier. The other eight tiers are unchanged. The backend retains the original 400-coin mapping for existing or unfinished purchases. It accepts `neiku_30` only for the test bundle in Sandbox; its price comes from Apple, not the old product's reference price.

Applied repairs `lulu_sandbox_test_identity` and `lulu_test_product` permit the exact test bundle and map `neiku_30` to 400 coins. They preserve existing balances, row security and service-only credit privileges. Unknown bundles remain rejected. The first repair keeps separate transaction keys and balances per bundle; no balance is copied between applications or environments. The test bundle selects Sandbox before its first receipt exists, while a successful verified delivery acknowledgment remains authoritative.

`travel-coin-purchase` version 3 now serves `status_by_id` and `deliver_by_id` as well as the earlier signed-JWS contract. Readback confirmed the deployed contract and test identifier. Forty-four isolated handler/API cases passed. The isolated PostgreSQL harness passed bundle isolation, duplicate delivery, ownership, guide spending and the test-product mapping checks. These checks do not establish Apple catalog availability, account permission or real wallet delivery.

## November 17 App Review purchase diagnosis

App Review reported that the balance stayed at zero after checkout in version 1.0 build 3. The submitted build's source revision and the specific review transaction were unavailable. Hosted function logs show seven version 2 delivery requests returned HTTP 422 on November 16 between 15:17 and 15:19 China Standard Time. Both Apple delivery ledgers contained zero entries during the read-only inspection. Supabase documents a failure mode that matches these observations. Edge Runtime's Node compatibility layer lacks X.509 methods required by Apple Server Library 3.1.0. The reported responses did not retain the individual verification exception. [Supabase Edge Runtime issue](https://github.com/supabase/edge-runtime/issues/761).

The client also had an independent defect. It could select the credited ledger from the signed transaction and then read the balance from a different, cached installation environment. It also ignored failures from the final balance read. The client now checks the acknowledgment environment, invalidates older wallet reads and refreshes the credited ledger before showing success. Failed or mismatched acknowledgments preserve the previous environment.

The corrected Edge Function uses Web Crypto and PKIjs for certificate-chain, signing-purpose, ES256 signature and live OCSP validation. The P-384/SHA-256 compatibility path uses Deno's direct signature primitive. The function separately reports verification outages, rejected transactions and ledger write failures. The account, product, quantity, environment, revocation and idempotency checks still apply. On Deno 2.1.4, the new verifier checked the Apple G3/G6 chain and accepted two live Apple-signed OCSP responses for public certificates. Synthetic signed transactions exercised the complete local verification path. The corrected verifier and StoreKit 1 contract were deployed as version 3 on November 17. A completed Apple sandbox purchase remains pending.

## November 16 repair status

This section supersedes older pending-verifier and local-default statements below. The purchase Edge Function was updated to version 2, and additive sandbox tables and RPCs were deployed. Public Apple identity is configured directly from the owner-confirmed app record; checkout no longer depends on an absent numeric Apple ID secret. Native transactions are verified against Sandbox or Production, with distinct ledgers. Sandbox credits and guide access are limited to authorized editorial content. Existing production balances and entitlements are unchanged.

Before the StoreKit 1 migration, all nine tiers passed isolated ledger tests and local StoreKit purchase tests. Apple sandbox device outcomes are recorded separately in the [November 16 evidence](../runtime-acceptance/2026-11-16-1030-purchase-repair/README.md).

## Guide access

The initial catalog has eight free guides. Colosseum and Ancient Rome costs 180 coins, Swiss Alps costs 260, Santorini Caldera Villages costs 140 and Moraine Lake, Banff costs 220. Preview information is visible separately from the restricted body. The server atomically records the debit and entitlement. A previous unlock survives future price changes. Destination covers display a Paid badge with the featured guide coin price. All destination entry routes refresh pricing and access before navigation. Unpurchased paid guides show their title, coin price and current balance in a confirmation dialog; Cancel leaves the current screen, Pay submits the expected price, and an insufficient balance offers Get coins. Navigation follows a committed unlock and refreshed content. Free guides, author-owned guides and previously unlocked guides open without another charge. The featured guide is the published editorial guide, or the first eligible published member guide when no editorial guide exists. Additional member guides retain their individual unlock controls inside the destination.

To submit a guide, open a destination and select **Write a guide for this place**. The author sets 0 to make it free or a whole coin amount through 10,000. **My guides** shows submissions and lets the author change their own price. New guides enter the pending queue. A moderator reviews the body and changes the corresponding `guide_offers.status` to `published` or `rejected` in the Supabase project. Pricing changes cannot approve a submission. Other accounts can report a published guide or block its member author.

## November 10 hosted evidence

The Supabase project applied migrations `20261110020657_lulu_coin_guides` and `20261110020907_scope_guide_author_visibility`. The second migration scopes the author-block check to the current account. Hosted checks found nine coin products, eight free guides, four paid guides and no ledger entries. An authenticated zero-balance test claim could read all 12 previews and only the eight free bodies through the existing snapshot or direct guide read. The same claim was denied an unlock for insufficient coins. The service-only credit RPC is denied to authenticated app clients. The Edge Function `travel-coin-purchase` version 1 is active and rejected an unsigned-in request with HTTP 401.

The numeric Apple ID and Apple storefront acceptance are pending. No real transaction, sandbox transaction, app build or simulator run was performed. Apple refund notifications and automated refund reconciliation are outside the initial delivery path.

## November 10 catalog diagnosis and client completion

All nine supplied/generated Lulu identifiers match the hosted `coin_products` rows and their quantities. No product IDs were missing from the app. The reported screenshot corresponds to a successful StoreKit response with no consumable products. This identifies the failing stage, not the Apple-side cause: App Store Connect registration, availability and agreement status remain unverified because no Apple administration access is connected.

The client now distinguishes loading, full/partial catalog, empty response, failure and a 20-second timeout. Requests are generation-scoped; sign-out and timeout invalidate stale callbacks. A returned partial catalog keeps eligible products usable. Purchase confirmation uses the actual localized StoreKit price, then rechecks the account, device restrictions and verifier before Apple's sheet. Pending/cancelled/failed purchases never credit coins. Signed transactions remain unfinished until authoritative ledger acknowledgment; explicit pending-purchase recovery and account-scoped update handling preserve this rule. Debug builds provide sanitized copyable diagnostics with requested/returned/missing IDs, catalog phase and bounded error domain/code. StoreKit 2 missing IDs are not mislabeled as explicit Apple invalid-ID responses.

`LuluApp/Configuration/LuluCoins.storekit` contains all nine matching consumables and reference prices and is an Xcode file-group reference only, excluded from app resources. On November 10 the Lulu scheme had StoreKit Configuration unset. The November 26 simulator default is documented in [Local StoreKit verification](local-storekit.md). The local fixture neither registers products in App Store Connect nor enables production ledger credit. Local Xcode and Apple sandbox transactions remain rejected by the production-only verifier. Full local/sandbox payment acceptance therefore requires a separate isolated test delivery design; it has not been claimed complete.

`lulu-product-comparison.csv` records the product mapping for comparison. The Release signing team is unassigned in the project. In-App Purchase capability metadata is recorded in the generator and project. Register products in App Store Connect separately.

Read-only hosted inspection confirmed the nine mappings and authenticated denial of direct credit RPC execution. Source inspection confirmed unique transaction-ID delivery, account/product matching on duplicates, atomic ledger writes and finish-after-acknowledgment. Runtime purchase acceptance is pending. No app build, typecheck, simulator run, local StoreKit transaction, sandbox transaction or production transaction was performed for this change.

## Owner-selected test signing

The owner selected `im.seex.sao2` and Yu Sun for testing. Debug uses that Bundle ID and Team ID `JPTS6M4T5B`, verified from the public subject of the installed Apple Development certificate (organization Yu Sun). The Lulu scheme runs Debug and archives Release. Release requires a distribution profile for `com.lulu.tourtravel`.

Static validation after metadata generation passed: the nine fixture IDs/prices match PaymentCatalog.json, all products are consumables, Debug identity/team and Release identity match the source configuration, the Lulu scheme runs Debug and archives Release, and the fixture is excluded from app resources. The two changed payment Swift files passed syntax parsing, the Xcode project passed plist lint, and whitespace checks passed. No compilation or runtime acceptance is implied by these checks.

## Local testing selected and verified

The prior pending test-mode notes are superseded: the owner selected Xcode local StoreKit. The Lulu Debug Run action now selects the nine-product fixture and the Debug-only local ledger. The full [local StoreKit verification report](local-storekit.md) records the successful build and three passing runtime tests, including nine purchases totaling 172,400 local coins. This does not establish Apple sandbox or production readiness.
