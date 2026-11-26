# Lulu company backend cutover

On November 26, 2026, the owner selected a single company backend and approved stopping writes on build 4 before shipping an updated binary. The active project is [Lulu in Thingtill Org](https://supabase.com/dashboard/project/ziryoihosvlqnbvfdvbw) in Ireland. The company organization is on Pro. Supabase quoted USD 10 per month for the additional project.

## Service ownership

The company project owns email/password Auth, guest upgrades, all application tables, RLS, canonical member identities, the Realtime publication, Storage and the verified Apple receipt ledger. The original [139 project](https://supabase.com/dashboard/project/dlbaneeshycwmhgfeokx) was restored to support previously issued guest credentials. New builds use company URLs for business reads, writes, content, legal agreements and payments.

Build 4 contains the original project URL. Its business RPC writes, Storage uploads, new signups and payment entry are retired. A fresh entry in build 4 fails. Existing old sessions can still refresh and obtain transfer tickets. Keep the original project available while guests upgrade. A Free-plan pause delays transfers for devices that still depend on this issuer. Fresh installations and completed transfers operate entirely on the company project.

## Guest ownership

1. An upgrading device uses distinct Keychain namespaces for the two issuers. It records the original member ID before refreshing the old session. A company guest session is saved before requesting a transfer.
2. The original issuer verifies the old login and issues a random, five-minute ticket bound to the destination Auth UUID. Only the ticket goes to the company service. Its redemption consumes the original database's stored digest.
3. The company entry function verifies its own session, redeems the ticket with the original project, and binds the verified identities through a service-only RPC. An already established, separate company profile cannot be merged through this path. A successful link survives network retries.
4. Business functions, RLS, Storage ownership checks and wallet delivery resolve the canonical member ID from a private link. Existing member IDs, friend codes, ownership, saved items and ledger entries retain their original values. The old local credential is cleared after successful entry, consent persistence and an identity-matched snapshot.

The 22 original anonymous member identities have been imported. Their 19 original session records remain at the original issuer. A device must still have a valid or renewable old session to prove ownership. The isolated acceptance exercise verified one full transfer. Individual member devices complete their transfers when they install and use the new build.

## Deployment and evidence

The company baseline reproduced all 22 original application function definitions before the identity changes. The company and original-project SQL files under `supabase/cutover/` target different projects. Apply each only to the project named in its opening comment. The original project's retired purchase handler returns an update requirement. The company deploys the normal receipt verifier. Account deletion retains its previous deployment gate.

After the source write fence, digests matched for all 163 original records across 28 compared relations. The 42 catalog files and four historical legal PDFs matched their source bytes on full downloads. Both current agreement PDFs were also published under the consent version and matched the bundle checksums. The company project has 48 Storage objects. One signed-out anonymous identity owns the imported public files. It has no public profile, session, or lasting upload permission. The separate guest handoff fixtures were removed.

A bounded hosted check exercised new anonymous entry, consent, snapshot, guest transfer, session refresh, saved-place visibility, isolation, and purchase readiness. Old business writes were denied and the old payment entry returned HTTP 503. The company receipt-readiness route succeeded for Sandbox and Production. No Apple transaction or device build was run in this cutover. The device upgrade and fresh-install paths still need acceptance on the new signed binary. [Verification record](company-cutover-evidence.json)

Supabase's security advisor still reports the intended guest access and authenticated definer exposure, an RLS-enabled private table without a client policy, and password protection for the unused password flow. Direct client execution of the identity-binding RPC and direct reads of the private identity links were denied by the effective grants.

The original deployment evidence in this directory is historical. The new and original projects use different asymmetric signing keys. [Supabase Auth project migration](https://supabase.com/kb/troubleshooting/migrating-auth-users-between-projects)
