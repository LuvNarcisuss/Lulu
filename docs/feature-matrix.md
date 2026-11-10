# Feature and Service Matrix

This matrix describes implemented source routes. The [November 10 functional acceptance report](runtime-acceptance/2026-11-10-1154-full-functional.md) records observed UI results and outstanding scenarios. Server evidence is maintained separately in `backend/integration.md` and its linked reports.

| Surface | Route | Authoritative operation | Boundary |
|---|---|---|---|
| Welcome and consent | EntryController | One-tap Supabase guest Auth or saved session, travel-entry, profile.update consent version | No external stage B; public PDF reading does not sign in |
| Short discovery | ShortsController / ShortsSearchController | Autoplay in the tab, with search and creation in the toolbar | Server-backed recorded footage, regional filters, saved videos and safety filtering |
| Film playback | ClipFeedController | Cloud public media or owner-authorized private submission | One AVPlayer, 1x, no playback after exit/background; no public interactions on private submissions |
| Comments and replies | CommentsController | comment.add / comment.delete | Server persistence; failed or newer typed input preserved |
| Travel uploads | CreationController | Private storage upload + submission.create | Real file/cover, own rights confirmation; private pending review, no automatic publication |
| Map and guides | ExploreController / PlaceController / MyGuidesController | Server catalog, creator submissions and pricing, paid unlocks and guide safety | Paid body is protected by server policy; creator submissions await review |
| Private journeys | JourneyEditorController / JourneyDetailController | journey.save / journey.delete | Auth owner, stable nested IDs, dated stops/checklist/budget/notes |
| Inbox and preferences | ChatsController | chat.preferences | Empty until user activity, real state, no seeded messages |
| Member discovery and groups | MemberDiscoveryController | chat.direct / chat.group | Actual non-editorial members only, canonical direct thread |
| Conversations | ConversationController | chat.send, read/draft preferences | Persistent text/photo/reply; realtime refresh and reconnect; no fabricated receipt or reply |
| Friend codes | FriendScannerController / TravelerCodeController | Strict travelapp friend UUID + actual member lookup | Explicit camera action, session stops outside active screen; never opens arbitrary scanned websites |
| Profile | MeController / PublicProfileController / EditProfileController | profile.update / relationship.follow | Actual record-derived counts; editorial publishers visibly identified |
| Safety | ReportController / SafetyHistoryController | safety.report / safety.unreport / safety.block | Real saved report/block, no claim of staffed moderation |
| Wallet | WalletController / PaymentCatalogAdapter | Nine StoreKit 2 consumables, Apple JWS verifier and server coin ledger | Checkout requires verification configuration and returned Apple product; no client credit |
| Agreements | AgreementController | Verified public PDFs + matching bundled PDF | Same entry/settings links; not production legal-operator approval |
| Sign out | SettingsController | SDK local signout, secure state cleanup | Does not delete cloud records; guest access may be unrecoverable |
| Own-account deletion | SettingsController / travel-account source | Not deployed | Explicit authorization absent; automatic review rejection disclosed; UI unavailable |
| Push | LaunchServices / AppDelegate | Callback and permission coordinator source | Signing identity/entitlement absent; registration feature disabled, no token fabrication |
