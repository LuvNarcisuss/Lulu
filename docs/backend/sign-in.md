# Email and password sign-in

Lulu uses Supabase Auth in the [company project](company-cutover.md). Every cold launch shows a full-screen travel illustration with the Lulu logo centered in the upper sky and a Welcome to Lulu button over the bottom of the cover. Tapping the button opens the sign-in form. Signing out returns directly to sign-in. The filled Sign in and Sign up buttons are active as soon as their forms appear. Below the primary action, a centered prompt ends with an underlined Sign up or Sign in button that switches forms. Switching forms retains the email and agreement checkbox state and clears both passwords.

Both forms show the agreement checkbox with separate links to the Terms of Service and Privacy Policy. Both require explicit agreement, a valid email address and a nonempty password. Registration also requires matching password confirmation. The app persists the consent version after password sign-in. Submitting an incomplete or invalid form opens the shared error alert and preserves the entered values. A request in progress disables repeat submission. Authentication failures use the same alert. Emails are trimmed and normalized to lowercase. Passwords retain their original bytes. The app adds no password composition rules. Supabase enforces a six-character minimum and email uniqueness. A confirmed registration shows Account created. OK returns to sign-in with the email retained and the passwords cleared.

## Account storage and access

The private Auth user table already provides the requested columns: `auth.users.email` and `auth.users.encrypted_password`. Supabase manages salted bcrypt hashes. Both fields are inaccessible to the anonymous and authenticated Data API roles. The public profile and application snapshots contain no credentials. [Supabase password storage](https://supabase.com/docs/guides/auth/password-security)

Email sessions use thread-safe, process-local storage and expire locally on a cold launch. The app opens the five tabs only after a password grant, an authenticated entry response, a consent-version write and a matching account snapshot. A fresh sign-up signs out its temporary registration session. Passwords stay in the form only until submission succeeds or the user switches modes. No OTP, magic link or email confirmation is part of account creation.

## Existing guests

A missing Keychain item means there is no saved credential for that key. Missing transfer markers are normal on first registration. Other Keychain read failures stop registration so the app cannot replace an inaccessible guest identity. Cleanup after a successful upgrade accepts an already-absent item.

On the original device, Sign up attaches email and password to the saved company guest. If the device still holds the original project's session, Lulu first finishes the existing ticket exchange with an anonymous company destination and checks the canonical ID. Anonymous provisioning is limited in the new client to that handoff. Fresh registrations use email signup. Signing into another email account uses separate session storage and leaves pending guest credentials available. Cleanup follows successful password sign-in to the upgraded identity and a matching snapshot.

## Verification

On November 26, 2026, the company Auth settings endpoint returned email enabled, signups enabled and `mailer_autoconfirm: true`. Database metadata confirmed both columns exist and neither client role has SELECT privileges on them.

Two disposable company identities exercised the public Auth, entry and business endpoints. Invalid email, short passwords, duplicate registration and incorrect credentials were rejected. A new account signed in directly after registration and logout. A company guest added email and password in one update and signed in with the same UUID. Each account persisted the agreement version, read an identity-matched snapshot with zero balance and empty journeys and messages, and had a bcrypt-formatted hash. Both disposable identities and their profiles were removed and their absence was verified. This check covered the hosted APIs. The original-issuer ticket exchange was previously checked during the cutover. Device upgrade and UI acceptance are pending.

The bundled and published agreements still describe the earlier guest flow. Their versioned PDFs require separate owner authorization for revision.
