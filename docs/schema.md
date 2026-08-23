# Database schema

Every application primary key is UUID and every mutable entity has `created_at` and `updated_at`. Foreign-key columns and dashboard/filter paths are indexed in the migration.

| Table | Important columns and constraints | Relationships |
|---|---|---|
| `profiles` | `id uuid PK`, `role user_role`, names/contact, `account_status`, timestamps | `id → auth.users.id` |
| `businesses` | `id uuid PK`, `profile_id UNIQUE`, business/PAN/contact/type, private document paths, QR path, KYC/verification/subscription states, admin-verified `vat_registered`, `vat_number`, `default_vat_rate`, rating cache, location | profile owns one business |
| `customers` | `id uuid PK`, `profile_id UNIQUE`, name/contact, identity metadata/path, KYC state | profile owns one customer |
| `invoices` | number, business/customer, `kind=payment_request`, dates (`due <= issue + 7`), payment method/status, `is_vat_invoice`, historical seller VAT number, server-generated monetary totals | business/customer; parent of items/payments |
| `invoice_items` | description/category, positive quantity and unit price, generated line total | invoice |
| `payments` | invoice, customer, amount, external reference/proof, status, marked/verified dates | invoice/customer/verifying profile |
| `transactions` | invoice `UNIQUE`, business/customer/payment, immutable `snapshot jsonb`, totals/payment date, IRD placeholder fields | created after verification |
| `transaction_events` | invoice/transaction, actor, event type, old/new status, metadata | append-only audit trail |
| `kyc_submissions` | profile, subject/document type/number/path, status, reviewer/comments | profile/reviewer |
| `reports` | invoice, reporter, reason/status, admin assignee/resolution | invoice/reporter |
| `reviews` | business/customer/transaction, 1–5 rating, one review per transaction | completed transaction proof |
| `support_tickets` | requester, subject/status/priority, assigned admin | profile |
| `support_messages` | ticket, sender, body/path, `is_internal` | internal rows restricted to admins |
| `subscriptions` | business, plan/status, dates with valid range | business |
| `admin_actions` | admin, target profile/business/invoice/report, action/reason/metadata | append-only admin audit |

Enums constrain all roles, lifecycle states, KYC states, report reasons, and IRD states. `set_updated_at` triggers maintain timestamps. Rating is maintained from reviews by trigger; dashboard money is always aggregated from verified transactions.

## Relationships

```text
auth.users 1--1 profiles 1--0..1 businesses
                      `--0..1 customers
businesses 1--* invoices *--1 customers
invoices   1--* invoice_items
           1--* payments
           1--0..1 transactions (immutable snapshot)
           1--* transaction_events
           1--* reports
profiles   1--* kyc_submissions / support_tickets / admin_actions
businesses 1--* reviews / subscriptions
```

## RLS model

- Profile owners read/update their own safe profile columns; transaction counterparties can read the minimum profile/business/customer records needed for a bill.
- Business owners manage only their business and invoices; customers read only invoices addressed to them.
- Direct writes to invoice items, payments, transactions and audit events are withheld. Validated RPCs perform stateful operations atomically.
- Admin checks query `profiles.role = 'admin'` and `account_status = 'active'`; no authorization depends on user-editable metadata.
- KYC/payment documents use private buckets and the first object-path segment must equal the uploader's Auth UUID. Admins can read all protected objects. Payment proof also allows the invoice's business owner to read it.
- Transactions, transaction events and admin actions reject update/delete even for ordinary authenticated users.
