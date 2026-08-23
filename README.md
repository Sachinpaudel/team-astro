# BillSathi

BillSathi includes a responsive React prototype based on the supplied Figma layout and is configured for the existing Supabase project **Hackfeast** (`pzgkxngxvineflxkmifz`). The current demo login and screen records remain local mock data while the database-backed authentication phase is built; the publishable Supabase client and schema are ready for that integration.

## UI prototype

Run it with:

```bash
npm install
npm run dev
```

Use the Business, Customer, or Admin tab on the demo login screen; any displayed credentials work because authentication is mocked for this UI phase. Included linked flows:

- Shared sign-in and two-step registration with PAN/non-PAN business documents, Fonepay QR, and customer identity documents
- Business pages: `/boverview`, `/binvoice`, `/binvoice/:id`, `/bcustomers`, `/bsettings`
- Customer pages: `/coverview`, `/cinvoice`, `/cinvoice/:id`, `/cdirectory`, `/csettings`
- Admin pages: `/averify`, `/areports`, `/asupport`, `/asettings`
- Negotiable invoice agreements with accept, reject, counter, and report actions
- Final VAT-aware Nepal tax bills and non-VAT bills with client-side PDF download
- Customer phone-number lookup, settings-based support-ticket creation, and responsive mock actions
- Responsive desktop/tablet/mobile navigation and searchable mock tables/directories

Frontend entry points live in `src/ui/`, with application routing in `src/ui/App.tsx` and the visual system in `src/ui/styles.css`.

## Backend foundation

BillSathi's backend foundation is implemented as a Supabase-first system: Supabase Auth owns credentials and sessions; PostgreSQL owns authorization, invoice calculations, payment state transitions, immutable final bills, audit history, and dashboard aggregates; private Supabase Storage buckets hold documents and payment evidence. The future frontend can use the small TypeScript client in `src/` or call the same RPCs directly.

## Architecture

```text
Web/mobile frontend (later)
        |
        | publishable key + user's JWT
        v
Supabase Auth ---- PostgreSQL Data API / RPC
                         |
                         +-- RLS-protected relational data
                         +-- transactional invoice/payment functions
                         +-- calculated dashboard functions
        |
        +---- Private Storage (owner-prefixed object paths)
```

Important boundaries:

- Passwords never enter application tables; `profiles.id` references `auth.users.id`.
- Roles live in `profiles`, not user-editable JWT metadata. Public signup only accepts `business` or `customer`; admins are promoted out-of-band by a trusted operator.
- Money is `numeric(14,2)`. Invoice totals are generated in PostgreSQL from items and a single VAT function.
- The final `transactions.snapshot` is created only after verification and is protected from updates/deletes.
- The browser never receives a secret/service-role key.
- This prototype includes IRD sync fields and a mock adapter only. It is not IRD/CBMS certified and makes no production IRD calls.

The full table and relationship catalogue is in [docs/schema.md](docs/schema.md).

## Repository layout

```text
supabase/config.toml                 local Supabase configuration
supabase/migrations/*_initial.sql    schema, RLS, storage, RPCs
supabase/tests/core_workflow.sql     pgTAP integration tests
src/auth.ts                          Auth/session facade
src/billsathi.ts                     typed invoice/payment/dashboard facade
src/ird.ts                           inert future-integration abstraction
src/index.ts                         exports
```

## Run locally

Requirements: Docker Desktop and Supabase CLI. The CLI is pinned locally, but Docker Desktop was not running on the current machine, so the included pgTAP suite is ready but was not executed here.

```bash
supabase start
supabase db reset
supabase test db
npm install
npm run typecheck
```

The repository pins Supabase CLI `2.115.0` as a development dependency, so `npx supabase ...` can be used in place of a global installation.

The ignored `.env.local` links this workspace to Hackfeast using only its browser-safe publishable key. Never place a service-role key in a `VITE_` variable.

The Hackfeast remote schema is authoritative. Do not push the older prototype migrations wholesale; apply reviewed incremental migrations such as `20260823021936_hackfeast_customer_identity_lookup.sql`.

## Core API flow

1. `auth.signUp()` creates an Auth user; the trigger creates its profile using only a validated `business` or `customer` role.
2. The user inserts their own `businesses` or `customers` row.
3. A business calls `create_invoice(customer_id, due_date, vat_rate, items, ...)`. PostgreSQL validates ownership and the 0–7 day deadline, calculates item totals/VAT, and records `invoice_created`.
4. The customer calls `mark_invoice_paid(invoice_id, reference, proof_path, note)`.
5. The business calls `review_payment(payment_id, true|false, note)`.
6. Confirmation locks the payment and invoice, marks them verified/paid, creates the immutable transaction snapshot, and appends an audit event in one database transaction.
7. Dashboard RPCs aggregate verified transactions; no editable dashboard totals exist.

## Deploy

Create/link a Supabase project, then run `supabase db push`. Review project Auth settings, configure production SMTP, and set short JWT expiry appropriate to the app's risk. Keep every configured Storage bucket private. Run database/security advisors before production.
