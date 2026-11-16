# Lulu purchase repair — November 16, 2026

## Scope and identity

Owner-confirmed Bundle ID: `com.lulu.tourtravel`; App Store Apple ID: `6832914128`; shared scheme: `Lulu`; internal target: `TravelApp`. Base commit: `37d596d78f3e913d64f87068dcd80aecfd8ada7c`, with preserved concurrent working-tree changes. Test destination: owner-designated iPhone 12, iOS 27.2.1, Xcode destination `00008101-0019755A3690001E`. No App Store Connect products or production payments were changed.

The owner ended further purchase acceptance on November 16 and requested a waiting animation. That direction ends the test run; it does not turn incomplete Apple purchase evidence into a pass.

## Repairs

- Unified Debug/Release identity; ordinary Run uses Apple StoreKit, with no local fixture or wallet variable.
- Corrected the hosted purchase verifier's bundle and Apple App ID, authenticated readiness and environment-specific verification. Deployed travel-coin-purchase version 2.
- Added independent Sandbox balances, idempotent delivery and editorial guide spending. Production ledger remains separate. Authenticated clients cannot mint credit; sandbox funds cannot unlock member-authored work.
- Replaced silently disabled unavailable package taps with feedback and retry. Retained guards against unverified credit.
- Recognize verified Xcode AppTransaction for explicit local tests; local balances remain separate.
- Added a fixed, noninteractive wallet loading card during `catalog.purchasing`, using the existing generated refresh icon. Rotation changes to an opacity animation for Reduce Motion. Success, cancellation, pending and failure clear the indicator when the purchase task returns. Native Apple UI remains system-owned.

## Coverage

| Layer | Expected | Observed | Evidence |
| --- | --- | --- | --- |
| Handler regression | Correct identity, environment, nine tiers, rejection paths | 18 passed; dependency-injected verifier/RPC, not live purchase proof | `scripts/tests/purchase-handler.test.mjs` |
| Signature rejection | Forged Sandbox/Production rejected | 2 passed using Apple server library 3.1.0 | `scripts/tests/runtime/signature-check.mjs` |
| Isolated PostgreSQL | Nine tiers total 172400, idempotency, owner isolation, separate spending | Passed; all synthetic fixtures rolled back; no hosted fixture insertion | `ledger-result.json`, `scripts/tests/sandbox-ledger.sql` |
| Local StoreKit | Nine purchases, duplicate protection, cancellation, ownership, persistence and guide spending | 7 tests passed, 0 failed/skipped on Lulu Purchase QA 20261110 | `local-storekit-summary.json` |
| Device build/install/launch | Current Lulu build on authorized phone | Succeeded; initial lockscreen blocker resolved by owner | `/private/tmp/lulu-payment-repair/device-build.log` |
| Real Apple catalog | All nine products with storefront prices | Returned, checkout readiness and Sandbox environment observed | `/private/tmp/LuluAppleSandboxRepair-20261116-02.xcresult` |
| Native Apple checkout | Apple no-charge Sandbox purchase sheet | 400-coin sheet appeared; attempt 03 returned userCancelled; attempt 04 waited for system password | Result bundles 02, 03, 04 below |
| Apple delivery | Verified purchase credits and persists each tier | Incomplete. No successful delivery established. Owner completed password; attempt 05 failed obtaining accessibility snapshots | `/private/tmp/LuluAppleSandboxRepair-20261116-05.xcresult` |
| Signing | Explicit App ID profile | Existing installed profile remains JPTS6M4T5B.*; automatic update build still selected wildcard | `/private/tmp/lulu-payment-repair/explicit-signing-build.log` |
| Loading animation | Visible while waiting; hidden on terminal result | Source and compile verification; no additional purchase/UI runtime run | `/private/tmp/lulu-payment-repair/payment-loading-build.log` |
| Production | Verified real payment and credit | Not exercised; no real charges authorized | Not applicable |

| Coins | Product | Local StoreKit | Apple sandbox |
| --- | --- | --- | --- |
| 400 | `iltpkpefqtjskxel` | Passed | Catalog returned; completed delivery not verified |
| 800 | `eweerqrczkwsjyjn` | Passed | Catalog returned; completed delivery not verified |
| 2,450 | `bfktecvbuyjzwxtp` | Passed | Catalog returned; completed delivery not verified |
| 5,150 | `zsadvhodvgamjqqp` | Passed | Catalog returned; completed delivery not verified |
| 10,800 | `qtqrufubdpyvzjzs` | Passed | Catalog returned; completed delivery not verified |
| 17,000 | `ipcijraguygtcpsa` | Passed | Catalog returned; completed delivery not verified |
| 29,400 | `azjrhiwubtjsrbzh` | Passed | Catalog returned; completed delivery not verified |
| 42,700 | `qjcdfljcmzajynnd` | Passed | Catalog returned; completed delivery not verified |
| 63,700 | `rzeethasxinmprew` | Passed | Catalog returned; completed delivery not verified |

## Evidence and boundaries

Local result bundle: `/private/tmp/LuluPurchaseRepair-20261116.xcresult`. Real-device attempts: `/private/tmp/LuluAppleSandboxRepair-20261116-02.xcresult`, `-03.xcresult`, `-04.xcresult`, and `-05.xcresult`. Raw native Apple captures remain in temporary storage because they include the sandbox account address; they are not copied into project documents. No passwords or signed transactions are recorded here.

Deployed SQL sources: `supabase/repairs/lulu_sandbox_purchases.sql` and follow-up `lulu_sandbox_editorial_scope.sql`. Initial requested hosted fixture validation was rejected by automatic review; validation moved to isolated PGlite. Only validated additive empty schema and the editorial restriction were subsequently deployed. No hosted synthetic credits were inserted.

The installed wildcard provisioning profile is a known configuration gap. Apple TN3186 requires an explicit App ID for sandbox IAP: https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox . The observed cancellation/password interruption does not by itself prove that signing was its sole cause.

## Reproduction

Use Node 24 for `node --test scripts/tests/purchase-handler.test.mjs`. Install pinned dependencies with `npm ci --prefix scripts/tests/runtime`; then run `node scripts/tests/runtime/ledger-check.mjs` and `node scripts/tests/runtime/signature-check.mjs`. Both are isolated checks, not Apple transaction acceptance.

Local tests explicitly load SKTestSession. The real-device UI test is opt-in through `TEST_RUNNER_LULU_SANDBOX_UI_TESTS=1` and must only be resumed with owner authorization, an available iPhone destination and a verified no-charge Sandbox sheet. Do not infer success from a returned product, native confirmation or the handler's readiness endpoint.
