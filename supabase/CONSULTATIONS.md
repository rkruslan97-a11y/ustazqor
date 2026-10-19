# Dated consultations

Apply `supabase/consultations.sql` on a fresh installation, then apply
`supabase/migrations/20261019_consultation_slots.sql` once in Supabase SQL Editor
as the database owner. Existing installations only need the migration. Deploy
`index.html` together with the migration. Never rerun the old consultations.sql
on a migrated installation: it reinstates obsolete write policies.

Teachers publish individual dated intervals (maximum four hours), in Kazakhstan
time (Asia/Oral, UTC+5). Parents and students see future unconfirmed slots and
their own request statuses. Different people may request the same interval;
only one request can be confirmed. Pending requests do not reserve an interval.
Repeat active requests from the same person are rejected. Declined requests can
be submitted again. Reviewed requests cannot be changed to a different status.
Published slots are immutable in this version.

RPCs enforce roles and ownership; direct booking writes are revoked. Row locking
serializes duplicate decisions. A partial GiST exclusion constraint prevents
confirmed interval overlaps even across concurrent transactions. Adjacent
intervals are allowed. No requester identities are exposed by the availability
RPC. Existing participant read policies remain in place. This relies on the
existing profiles role administration being trustworthy.

Historical requests retain labels and statuses, with null dated fields. Historical
pending requests can be declined but cannot be confirmed. Ask those users to
select a newly published interval. Review historical confirmed labels manually:
their calendar dates cannot be recovered safely and are not reserved as dated
intervals by this migration.

Run tests only against an EMPTY disposable PostgreSQL database as its owner:
`DATABASE_URL=postgresql://... python3 tests/consultations.py`.
The suite creates minimal auth/profile fixtures, tests roles, repeat and concurrent
requests, concurrent decisions, decline/reapply, legacy requests, schedule
overlaps and adjacency. GitHub Actions supplies a disposable PostgreSQL 16 service.
Never point the test suite at a production Supabase database.
