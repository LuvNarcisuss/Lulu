# One-Tap Sign-In

The welcome screen is Lulu's only entry screen. It retains the travel cover at the top and the title, tagline, agreement checkbox, linked Terms of Service and Privacy Policy, and Start exploring button near the bottom on one non-scrolling page. There is no separate sign-in page.

With consent checked, Start exploring immediately begins authentication and opens the application after success. With consent unchecked, it opens the agreement dialog. Agree and log in checks consent and starts the same authentication flow directly; Disagree dismisses the dialog without signing in. Both policy links remain available from the welcome screen and dialog. Returning from an agreement preserves the checkbox state.

Authentication shows an activity indicator in Start exploring and disables repeated entry and checkbox changes. Failure leaves the user on the welcome screen with their selection preserved and a retry message. Entry copy contains no guest labels or session-loss explanations.

The shared entry operation restores the existing project-scoped Supabase session or signs in anonymously if there is no saved session. A retry after a successful Auth response restores that same session, including when profile loading failed. Entry requires a matching saved session, a successful authenticated `travel-entry` response, a consent-version write, and an authenticated snapshot. Realtime starts after authentication succeeds.

The Auth UUID links to the profile used by Me and Edit Profile. A new guest starts with the display name Traveler, no custom avatar, and a zero wallet balance. Settings warns before guest sign-out because loss of the saved session can make the account inaccessible.

On November 9, 2026, the hosted settings endpoint reported anonymous sign-in and new user sign-ups enabled for project `dlbaneeshycwmhgfeokx`. An aggregate Auth query reported zero accounts before the switch. The existing project and its session storage are reused. This change was checked statically and did not create a verification account.

The former Apple and email/password forms are historical. The email configuration remains available at the provider level. Lulu's current entry uses the guest flow.
