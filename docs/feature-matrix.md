# Feature and Service Matrix

This matrix describes implemented source routes. Runtime UI acceptance is unperformed. Server evidence is maintained separately in `backend/integration.md` and its linked reports.

| Surface | Route | Authoritative operation | Boundary |
|---|---|---|---|
| Welcome and consent | EntryController | Real guest Auth, travel-entry, profile.update consent version | No external stage B; public PDF reading does not sign in |
| Short discovery | ShortsController | Server clips/places and actual personal collections | Recorded footage, no fake live broadcast or engagement |
| Film playback | ClipFeedController | Cloud public media or owner-authorized private submission | One AVPlayer, 1x, no playback after exit/background; no public interactions on private submissions |
| Comments and replies | CommentsController | comment.add / comment.delete | Server persistence; failed or newer typed input preserved |
| Travel uploads | CreationController | Private storage upload + submission.create | Real file/cover, own rights confirmation; private pending review, no automatic publication |
| Map and guides | ExploreController / PlaceController | Server places/guides, place.save | Official sources linked; no invented booking or live location |
| Private journeys | JourneyEditorController / JourneyDetailController | journey.save / journey.delete | Auth owner, stable nested IDs, dated stops/checklist/budget/notes |
| Inbox and preferences | ChatsController | chat.preferences | Empty until user activity, real state, no seeded messages |
| Member discovery and groups | MemberDiscoveryController | chat.direct / chat.group | Actual non-editorial members only, canonical direct thread |
| Conversations | ConversationController | chat.send, read/draft preferences | Persistent text/photo/reply; realtime refresh and reconnect; no fabricated receipt or reply |
| Friend codes | FriendScannerController / TravelerCodeController | Strict travelapp friend UUID + actual member lookup | Explicit camera action, session stops outside active screen; never opens arbitrary scanned websites |
| Profile | MeController / PublicProfileController / EditProfileController | profile.update / relationship.follow | Actual record-derived counts; editorial publishers visibly identified |
| Safety | ReportController / SafetyHistoryController | safety.report / safety.unreport / safety.block | Real saved report/block, no claim of staffed moderation |
| Wallet | WalletController / PaymentCatalogAdapter | Server zero balance/history + actual SKProductsRequest | Missing IDs disabled; no payment or unverified credit endpoint |
| Agreements | AgreementController | Verified public PDFs + matching bundled PDF | Same entry/settings links; not production legal-operator approval |
| Sign out | SettingsController | SDK local signout, secure state cleanup | Does not delete cloud records; guest access may be unrecoverable |
| Own-account deletion | SettingsController / travel-account source | Not deployed | Explicit authorization absent; automatic review rejection disclosed; UI unavailable |
| Push | LaunchServices / AppDelegate | Callback and permission coordinator source | Signing identity/entitlement absent; registration feature disabled, no token fabrication |
