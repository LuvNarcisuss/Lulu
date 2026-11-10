# One-Tap Sign-In

The welcome and one-tap sign-in pages use the same cover size at the top. Both pages keep the title and actions together at the bottom, above the safe area. The welcome group includes the agreement checkbox and inline links to Terms of Service and Privacy Policy. Starting with the box unchecked opens a consent dialog with both links. Agree and log in accepts the agreements and starts the same one-tap flow as the Log in button. Disagree dismisses the dialog and leaves the checkbox unchecked.

Log in restores the existing project-scoped Supabase session or signs in anonymously if there is no saved session. A retry after a successful Auth response restores that same session, including when profile loading failed. Entry requires a matching saved session, a successful authenticated `travel-entry` response, a consent-version write, and an authenticated snapshot. Realtime starts after authentication succeeds.

The Auth UUID links to the profile used by Me and Edit Profile. A new guest starts with the display name Traveler, no custom avatar, and a zero wallet balance. Settings warns before guest sign-out because loss of the saved session can make the account inaccessible.

On November 9, 2026, the hosted settings endpoint reported anonymous sign-in and new user sign-ups enabled for project `dlbaneeshycwmhgfeokx`. An aggregate Auth query reported zero accounts before the switch. The existing project and its session storage are reused. This change was checked statically and did not create a verification account.

The former Apple and email/password forms are historical. The email configuration remains available at the provider level. Lulu's current entry uses the guest flow.
