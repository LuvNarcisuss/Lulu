# Coins and paid guides

The wallet uses StoreKit 2 consumable products. Ordinary Debug and Release now use Apple-backed purchases for the owner-confirmed `com.lulu.tourtravel` / `6832914128` identity. Local StoreKit remains explicitly available through the isolated test target described in [Local StoreKit verification](local-storekit.md). The values below are the US reference mapping. The app displays Apple's returned storefront price and only offers checkout when Apple returns the product and the verifier is configured.

| Reference USD | Coins | Product ID |
| ---: | ---: | --- |
| 0.99 | 400 | `iltpkpefqtjskxel` |
| 1.99 | 800 | `eweerqrczkwsjyjn` |
| 4.99 | 2,450 | `bfktecvbuyjzwxtp` |
| 9.99 | 5,150 | `zsadvhodvgamjqqp` |
| 19.99 | 10,800 | `qtqrufubdpyvzjzs` |
| 29.99 | 17,000 | `ipcijraguygtcpsa` |
| 49.99 | 29,400 | `azjrhiwubtjsrbzh` |
| 69.99 | 42,700 | `qjcdfljcmzajynnd` |
| 99.99 | 63,700 | `rzeethasxinmprew` |

The two new product IDs are for the 29.99 and 69.99 tiers. Register them for Lulu in App Store Connect and confirm the seven supplied IDs are on the same app. Codemagic uses Apple ID `6832914128`. Confirm that the record uses `com.lulu.tourtravel` before deploying the updated verifier and setting `APPLE_APP_ID` in its Edge Function environment. The local verifier source targets `com.lulu.tourtravel` and uses Apple Root CA G3 and Apple's pinned server library. Deployment of the identity change is pending. The verifier checks production consumables, the signed account token, product identity and quantity before calling the service-only ledger. The transaction is finished on iOS only after the ledger acknowledges it. Unfinished transactions can be retried. Sandbox and local StoreKit purchases do not credit the production ledger.

## November 16 repair status

This section supersedes older pending-verifier and local-default statements below. The purchase Edge Function was updated to version 2, and additive sandbox tables and RPCs were deployed. Public Apple identity is configured directly from the owner-confirmed app record; checkout no longer depends on an absent numeric Apple ID secret. Native transactions are verified against Sandbox or Production, with distinct ledgers. Sandbox credits and guide access are limited to authorized editorial content. Existing production balances and entitlements are unchanged.

All nine tiers passed isolated ledger tests and local StoreKit purchase tests. Actual Apple sandbox device outcomes are recorded separately in the [current evidence](../runtime-acceptance/2026-11-16-1030-purchase-repair/README.md). Do not infer sandbox or production purchase completion from those local tests.

## Guide access

The initial catalog has eight free guides. Colosseum and Ancient Rome costs 180 coins, Swiss Alps costs 260, Santorini Caldera Villages costs 140 and Moraine Lake, Banff costs 220. Preview information is visible separately from the restricted body. The server atomically records the debit and entitlement. A previous unlock survives future price changes. Destination covers display a Paid badge with the featured guide coin price. All destination entry routes refresh pricing and access before navigation. Unpurchased paid guides show their title, coin price and current balance in a confirmation dialog; Cancel leaves the current screen, Pay submits the expected price, and an insufficient balance offers Get coins. Navigation follows a committed unlock and refreshed content. Free guides, author-owned guides and previously unlocked guides open without another charge. The featured guide is the published editorial guide, or the first eligible published member guide when no editorial guide exists. Additional member guides retain their individual unlock controls inside the destination.

To submit a guide, open a destination and select **Write a guide for this place**. The author sets 0 to make it free or a whole coin amount through 10,000. **My guides** shows submissions and lets the author change their own price. New guides enter the pending queue. A moderator reviews the body and changes the corresponding `guide_offers.status` to `published` or `rejected` in the Supabase project. Pricing changes cannot approve a submission. Other accounts can report a published guide or block its member author.

## Hosted evidence

The Supabase project applied migrations `20261110020657_lulu_coin_guides` and `20261110020907_scope_guide_author_visibility`. The second migration scopes the author-block check to the current account. Hosted checks found nine coin products, eight free guides, four paid guides and no ledger entries. An authenticated zero-balance test claim could read all 12 previews and only the eight free bodies through the existing snapshot or direct guide read. The same claim was denied an unlock for insufficient coins. The service-only credit RPC is denied to authenticated app clients. The Edge Function `travel-coin-purchase` version 1 is active and rejected an unsigned-in request with HTTP 401.

The numeric Apple ID and Apple storefront acceptance are pending. No real transaction, sandbox transaction, app build or simulator run was performed. Apple refund notifications and automated refund reconciliation are outside the initial delivery path.

## November 10 catalog diagnosis and client completion

All nine supplied/generated Lulu identifiers match the hosted `coin_products` rows and their quantities. No product IDs were missing from the app. The reported screenshot corresponds to a successful StoreKit response with no consumable products. This identifies the failing stage, not the Apple-side cause: App Store Connect registration, availability and agreement status remain unverified because no Apple administration access is connected.

The client now distinguishes loading, full/partial catalog, empty response, failure and a 20-second timeout. Requests are generation-scoped; sign-out and timeout invalidate stale callbacks. A returned partial catalog keeps eligible products usable. Purchase confirmation uses the actual localized StoreKit price, then rechecks the account, device restrictions and verifier before Apple's sheet. Pending/cancelled/failed purchases never credit coins. Signed transactions remain unfinished until authoritative ledger acknowledgment; explicit pending-purchase recovery and account-scoped update handling preserve this rule. Debug builds provide sanitized copyable diagnostics with requested/returned/missing IDs, catalog phase and bounded error domain/code. StoreKit 2 missing IDs are not mislabeled as explicit Apple invalid-ID responses.

`LuluApp/Configuration/LuluCoins.storekit` contains all nine matching consumables and reference prices and is an Xcode file-group reference only, excluded from app resources. The existing Lulu scheme keeps StoreKit Configuration unset (Apple catalog mode). Select this file manually in the same scheme only for authorized local catalog checks; select None to return to Apple's catalog. The local fixture neither registers products in App Store Connect nor enables production ledger credit. Local Xcode and Apple sandbox transactions remain rejected by the production-only verifier. Full local/sandbox payment acceptance therefore requires a separate isolated test delivery design; it has not been claimed complete.

`lulu-product-comparison.csv` records the product mapping for comparison. The Release signing team is unassigned in the project. In-App Purchase capability metadata is recorded in the generator and project. Register products in App Store Connect separately.

Read-only hosted inspection confirmed the nine mappings and authenticated denial of direct credit RPC execution. Source inspection confirmed unique transaction-ID delivery, account/product matching on duplicates, atomic ledger writes and finish-after-acknowledgment. Runtime purchase acceptance is pending. No app build, typecheck, simulator run, local StoreKit transaction, sandbox transaction or production transaction was performed for this change.

## Owner-selected test signing

The owner selected `im.seex.sao2` and Yu Sun for testing. Debug uses that Bundle ID and Team ID `JPTS6M4T5B`, verified from the public subject of the installed Apple Development certificate (organization Yu Sun). The Lulu scheme runs Debug and archives Release. Release requires a distribution profile for `com.lulu.tourtravel`.

Static validation after metadata generation passed: the nine fixture IDs/prices match PaymentCatalog.json, all products are consumables, Debug identity/team and Release identity match the source configuration, the Lulu scheme runs Debug and archives Release, and the fixture is excluded from app resources. The two changed payment Swift files passed syntax parsing, the Xcode project passed plist lint, and whitespace checks passed. No compilation or runtime acceptance is implied by these checks.

## Local testing selected and verified

The prior pending test-mode notes are superseded: the owner selected Xcode local StoreKit. The Lulu Debug Run action now selects the nine-product fixture and the Debug-only local ledger. The full [local StoreKit verification report](local-storekit.md) records the successful build and three passing runtime tests, including nine purchases totaling 172,400 local coins. This does not establish Apple sandbox or production readiness.
