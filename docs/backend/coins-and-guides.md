# Coins and paid guides

The wallet uses StoreKit 2 consumable products. The values below are the US reference mapping. The app displays Apple's returned storefront price and only offers checkout when Apple returns the product and the verifier is configured.

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

The two new product IDs are for the 29.99 and 69.99 tiers. Register them for Lulu in App Store Connect and confirm the seven supplied IDs are on the same app. Set the verified numeric Apple ID in the Edge Function environment as `APPLE_APP_ID`. The verifier uses `com.lulu.travel`, Apple Root CA G3 and Apple's pinned server library. It verifies production consumables, the signed account token, product identity and quantity before calling the service-only ledger. The transaction is finished on iOS only after the ledger acknowledges it. Unfinished transactions can be retried. Sandbox and local StoreKit purchases do not credit the production ledger.

## Guide access

The initial catalog has eight free guides. Colosseum and Ancient Rome costs 180 coins, Swiss Alps costs 260, Santorini Caldera Villages costs 140 and Moraine Lake, Banff costs 220. Preview information is visible separately from the restricted body. The server atomically records the debit and entitlement. A previous unlock survives future price changes.

To submit a guide, open a destination and select **Write a guide for this place**. The author sets 0 to make it free or a whole coin amount through 10,000. **My guides** shows submissions and lets the author change their own price. New guides enter the pending queue. A moderator reviews the body and changes the corresponding `guide_offers.status` to `published` or `rejected` in the Supabase project. Pricing changes cannot approve a submission. Other accounts can report a published guide or block its member author.

## Hosted evidence

The Supabase project applied migrations `20261110020657_lulu_coin_guides` and `20261110020907_scope_guide_author_visibility`. The second migration scopes the author-block check to the current account. Hosted checks found nine coin products, eight free guides, four paid guides and no ledger entries. An authenticated zero-balance test claim could read all 12 previews and only the eight free bodies through the existing snapshot or direct guide read. The same claim was denied an unlock for insufficient coins. The service-only credit RPC is denied to authenticated app clients. The Edge Function `travel-coin-purchase` version 1 is active and rejected an unsigned-in request with HTTP 401.

The numeric Apple ID and Apple storefront acceptance are pending. No real transaction, sandbox transaction, app build or simulator run was performed. Apple refund notifications and automated refund reconciliation are outside the initial delivery path.
