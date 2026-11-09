# Independent Static Review

Review date: 2026-11-03. Scope: current `TravelApp/Sources/Core`, `Design`, `Features`, `project.yml`, `Info.plist`, and referenced asset/font metadata. The project has no committed baseline; current files were reviewed directly. Backend implementation is assigned separately and was not reviewed for completeness.

No compilation, typechecking, app launch, simulator, Preview, or runtime test was performed. This report does not establish build success or device acceptance.

## Final static disposition

No unresolved Critical or Important finding remains from this review's inspected scope after the coordinator's fixes were reread. This is a static disposition only; backend integration, Swift type compatibility, and device acceptance remain outside the evidence obtained here.

## Findings corrected during review

1. **P2 — Clip visibility before initial playback and page activation.** The original feed activated any supplied clip; its initial safety refresh returned while `activeIndex == -1`. Place/profile/saved routes could therefore reopen a previously blocked or reported clip. Verified correction: `ClipFeedController.swift:33–50` filters incoming clips through `visibleClip`, resolves canonical catalog records, and checks owned private submissions. `activate` rechecks that predicate, and revision refresh rechecks availability. Empty feeds include a back action.

2. **P2 — Preserve text and reply changes made while a comment is sending.** The original comment success path cleared the composer and reply target unconditionally, erasing changes entered while persistence was pending. Verified correction: `CommentsController.swift:59–73` snapshots the raw input and reply ID, submits that snapshot, and clears only values that still match it.

- The initial journey editor changed the date range without rebuilding existing day records. The current `JourneyControllers.swift:102–119` reschedules days, preserves retained day IDs/stops/notes, adds days, and requests confirmation before trimming days containing data.
- The initial journey implementation mixed UTC date parsing with device-time-zone calendar arithmetic. The current shared calendar at `JourneyControllers.swift:134–139` explicitly uses UTC for parsing and day arithmetic.

## Static observations

- Player status, loop, and foreground callbacks route playback through `resumeIfAllowed`, which checks screen activity, modal coverage, manual pause, app activity, and item readiness. Leaving the screen sets `isActive = false` and pauses the player.
- Video imports copy the provider-owned temporary file synchronously inside its callback, then work on the app-owned copy. Cleanup targets app-created temporary files. Photo import reads provider bytes inside the provider callback and returns bounded JPEG data; no original Photos deletion API was found.
- Scene startup explicitly assigns `SceneDelegate`; the scene manifest and custom friend URL scheme are present. The tab selector computes dock visibility from the selected navigation stack.
- No SF Symbols or system-font fallback was found in the inspected source. Direct parsing of packaged TrueType name tables confirmed `Kalam-Regular`, `Kalam-Bold`, and `FrauncesTravelDisplay-Semibold`, matching the configured names. Every filename referenced by the asset catalog JSON files exists.
- The project source config enables iPhone only, portrait, iOS 16+, and disables Catalyst, Mac compatibility, and Vision compatibility. Missing owner identity and product IDs remain documented release dependencies rather than review defects.
- API type compatibility and layout on actual device sizes remain unverified because the owner has not authorized compilation or runtime validation.

The date/time concern was checked against [Apple's default-time-zone documentation](https://developer.apple.com/documentation/foundation/nstimezone/default), which states that the system zone supplies the default when no override is set.

## Scoped addendum: startup services and read-failure overlay

This bounded follow-up reviews only the newly added `Core/LaunchServices.swift`, its entry/AppDelegate wiring in `Core/Application.swift`, and `ServerReadFailureOverlay` plus its base-screen installation in `Design/TravelDesign.swift`. The updated one-tap skill and its stage-A authentication reference were reread. Store call sites were inspected only to trace the gate and published error inputs. No compilation, typecheck, dependency resolution, launch, or runtime test was performed.

### Important finding

- **P2 — Invalidate network readiness after a real transport failure.** At `Core/LaunchServices.swift:129–131`, a previously successful HEAD probe causes every later consumer to return immediately. The only external invalidation call sites are reachability changes and backgrounding (`:120`, `:125`); `invalidate` is private (`:141`). A transport error from the subsequent Supabase Auth/bootstrap request therefore cannot revoke readiness. If DNS, app network permission, or transport connectivity fails while the route remains unchanged, a second login skips the required bounded readiness wait and directly retries the failing authentication chain. Add a transport-error-only invalidation entry point and wire the real request failures to it; HTTP business responses must not trigger re-probing. This follows the updated stage-A requirement that pure network errors invalidate the corresponding origin's readiness.

### Other scoped observations

- One application-owned coordinator retains the reachability listener. The probe uses ephemeral URLSession, HEAD to the configured project origin, finite timeouts, no business headers/body, and a redirect delegate that declines redirect requests. Any actual HTTP response marks only reachability.
- Waiters have independent cancellation and 30-second active-time budgets. Inactive transitions pause those budgets; foreground resumes them. Probe retry uses the specified bounded backoff and background invalidation.
- Installation UUID storage is separate from Auth identity, uses Keychain, rereads the authoritative stored value, and throws on storage errors rather than manufacturing another usable identity.
- Entry obtains its submit lock before awaiting login and uses button text plus activity indicator. The inspected login call site creates an anonymous user only for `AuthError.sessionMissing`, not arbitrary network errors.
- The read-failure overlay observes the published read error and authentication state, shows an opaque themed error surface, and retries the real store refresh. It does not substitute catalog data.
- APNs callbacks are scaffolded. `PushRegistrationEnabled` is false pending the owner's signing identity and entitlement configuration; notifications are not represented as operational or validated.

The finding above is the only Important finding from this bounded addendum. The earlier full-source static disposition does not certify these later changes or app runtime behavior.

### Coordinator correction after scoped review

The transport-readiness finding is resolved in source. `AppNetworkGate.markTransportFailure` now invalidates readiness only for URLError-domain transport failures (bounded underlying-error traversal; cancellation excluded). TravelStore invokes it from actual Auth, URLSession and Storage failure paths; HTTP/business responses do not invoke a new authentication attempt. Static source tracing confirmed these call sites. This correction has not been compiled or exercised on a device.

The video rail and caption area were additionally made independently scrollable for constrained height and Dynamic Type; hidden arranged controls use priority 999 size requirements so UIStackView can collapse them without an equal-priority height conflict. Device layout acceptance is still open.
