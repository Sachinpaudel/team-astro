begin;

create extension if not exists pgcrypto;

create type public.user_role as enum ('business', 'customer', 'admin');
create type public.account_status as enum ('active', 'restricted', 'suspended');
create type public.kyc_status as enum ('not_submitted', 'pending', 'verified', 'rejected', 'additional_information_required');
create type public.business_type as enum ('service_provider', 'store', 'freelancer', 'repair_service', 'restaurant', 'other');
create type public.invoice_status as enum ('draft', 'sent', 'viewed', 'verification_pending', 'paid', 'payment_rejected', 'cancelled');
create type public.payment_status as enum ('verification_pending', 'verified', 'rejected');
create type public.report_reason as enum ('incorrect_amount', 'service_not_provided', 'duplicate_invoice', 'suspicious_invoice', 'payment_dispute', 'unauthorized_transaction', 'possible_fraud', 'other');
create type public.review_status as enum ('open', 'under_review', 'resolved', 'dismissed');
create type public.ticket_status as enum ('open', 'in_progress', 'waiting_for_user', 'resolved', 'closed');
create type public.subscription_status as enum ('trial', 'active', 'expired', 'cancelled');
create type public.ird_sync_status as enum ('pending', 'synced', 'failed', 'not_required');
create type public.transaction_event_type as enum ('invoice_created', 'invoice_sent', 'invoice_viewed', 'customer_marked_paid', 'payment_verified', 'payment_rejected', 'invoice_overdue', 'report_created', 'admin_action');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null,
  full_name text not null check (length(trim(full_name)) between 2 and 150),
  phone text,
  email text,
  account_status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index profiles_phone_unique on public.profiles(phone) where phone is not null;
create unique index profiles_email_lower_unique on public.profiles(lower(email)) where email is not null;

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  business_name text not null check (length(trim(business_name)) between 2 and 200),
  pan_number text not null unique check (length(trim(pan_number)) between 5 and 30),
  pan_document_path text,
  registration_document_path text,
  owner_contact_name text not null,
  phone text not null,
  email text,
  address text not null,
  business_type public.business_type not null,
  custom_business_type text,
  fonepay_qr_path text,
  kyc_status public.kyc_status not null default 'not_submitted',
  is_verified boolean not null default false,
  subscription_status public.subscription_status not null default 'trial',
  rating numeric(3,2) not null default 0 check (rating between 0 and 5),
  rating_count integer not null default 0 check (rating_count >= 0),
  latitude numeric(9,6) check (latitude between -90 and 90),
  longitude numeric(9,6) check (longitude between -180 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint custom_business_type_required check (business_type <> 'other' or nullif(trim(custom_business_type), '') is not null)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  full_name text not null,
  phone text not null,
  email text,
  identity_document_type text check (identity_document_type in ('citizenship', 'national_id', 'driving_license', 'passport')),
  identity_document_number text,
  identity_document_path text,
  kyc_status public.kyc_status not null default 'not_submitted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index customers_phone_unique on public.customers(phone);

create sequence public.invoice_number_seq;

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique default ('BS-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(nextval('public.invoice_number_seq')::text, 6, '0')),
  business_id uuid not null references public.businesses(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  kind text not null default 'payment_request' check (kind = 'payment_request'),
  issue_date date not null default current_date,
  due_date date not null,
  payment_method text not null default 'fonepay_qr',
  status public.invoice_status not null default 'sent',
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  vat_rate numeric(5,2) not null default 0 check (vat_rate between 0 and 100),
  vat_amount numeric(14,2) not null default 0 check (vat_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoice_due_window check (due_date between issue_date and issue_date + 7)
);

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  description text not null check (length(trim(description)) between 1 and 500),
  category text,
  quantity numeric(12,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(14,2) generated always as (round(quantity * unit_price, 2)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  status public.payment_status not null default 'verification_pending',
  payment_reference text,
  proof_path text,
  customer_note text,
  business_note text,
  marked_paid_at timestamptz not null default now(),
  verified_at timestamptz,
  verified_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index payments_one_pending_or_verified on public.payments(invoice_id) where status in ('verification_pending', 'verified');

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_number text not null unique,
  invoice_id uuid not null unique references public.invoices(id) on delete restrict,
  payment_id uuid not null unique references public.payments(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  subtotal numeric(14,2) not null,
  vat_rate numeric(5,2) not null,
  vat_amount numeric(14,2) not null,
  total_amount numeric(14,2) not null,
  payment_date timestamptz not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  ird_sync_status public.ird_sync_status not null default 'not_required',
  ird_reference text,
  synced_at timestamptz,
  sync_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.transaction_events (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid references public.invoices(id) on delete restrict,
  transaction_id uuid references public.transactions(id) on delete restrict,
  actor_profile_id uuid references public.profiles(id) on delete set null,
  event_type public.transaction_event_type not null,
  previous_status text,
  new_status text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  constraint event_has_subject check (invoice_id is not null or transaction_id is not null)
);

create table public.kyc_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  subject_type public.user_role not null check (subject_type in ('business', 'customer')),
  document_type text not null,
  document_number text,
  document_path text not null,
  status public.kyc_status not null default 'pending' check (status <> 'not_submitted'),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewer_comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  reporter_profile_id uuid not null references public.profiles(id) on delete restrict,
  reason public.report_reason not null,
  details text,
  status public.review_status not null default 'open',
  assigned_admin_id uuid references public.profiles(id) on delete set null,
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(invoice_id, reporter_profile_id, reason)
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  transaction_id uuid not null unique references public.transactions(id) on delete restrict,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references public.profiles(id) on delete restrict,
  subject text not null,
  status public.ticket_status not null default 'open',
  priority smallint not null default 2 check (priority between 1 and 4),
  assigned_admin_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  sender_profile_id uuid not null references public.profiles(id) on delete restrict,
  body text not null check (length(trim(body)) > 0),
  attachment_path text,
  is_internal boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan text not null,
  status public.subscription_status not null default 'trial',
  start_date date not null,
  expiry_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expiry_date >= start_date)
);

create table public.admin_actions (
  id uuid primary key default gen_random_uuid(),
  admin_profile_id uuid not null references public.profiles(id) on delete restrict,
  target_profile_id uuid references public.profiles(id) on delete restrict,
  target_business_id uuid references public.businesses(id) on delete restrict,
  target_invoice_id uuid references public.invoices(id) on delete restrict,
  target_report_id uuid references public.reports(id) on delete restrict,
  action text not null,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

create index businesses_profile_idx on public.businesses(profile_id);
create index businesses_nearby_idx on public.businesses(business_type, is_verified, rating desc);
create index customers_profile_idx on public.customers(profile_id);
create index invoices_business_status_due_idx on public.invoices(business_id, status, due_date);
create index invoices_customer_status_due_idx on public.invoices(customer_id, status, due_date);
create index invoice_items_invoice_idx on public.invoice_items(invoice_id);
create index payments_invoice_idx on public.payments(invoice_id, created_at desc);
create index payments_customer_idx on public.payments(customer_id, created_at desc);
create index transactions_business_date_idx on public.transactions(business_id, payment_date desc);
create index transactions_customer_date_idx on public.transactions(customer_id, payment_date desc);
create index transaction_events_invoice_date_idx on public.transaction_events(invoice_id, created_at);
create index kyc_profile_status_idx on public.kyc_submissions(profile_id, status);
create index reports_status_date_idx on public.reports(status, created_at);
create index support_tickets_requester_idx on public.support_tickets(requester_profile_id, created_at desc);
create index support_messages_ticket_idx on public.support_messages(ticket_id, created_at);
create index subscriptions_business_status_idx on public.subscriptions(business_id, status);
create index admin_actions_admin_date_idx on public.admin_actions(admin_profile_id, created_at desc);

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;

create or replace function public.is_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin' and p.account_status = 'active');
$$;

create or replace function public.owns_business(p_business_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.businesses b join public.profiles p on p.id = b.profile_id where b.id = p_business_id and b.profile_id = (select auth.uid()) and p.account_status = 'active');
$$;

create or replace function public.owns_customer(p_customer_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.customers c join public.profiles p on p.id = c.profile_id where c.id = p_customer_id and c.profile_id = (select auth.uid()) and p.account_status = 'active');
$$;

create or replace function public.calculate_invoice_totals(p_subtotal numeric, p_vat_rate numeric)
returns table(subtotal numeric, vat_amount numeric, total_amount numeric)
language sql immutable set search_path = '' as $$
  select round(p_subtotal, 2), round(p_subtotal * p_vat_rate / 100, 2), round(p_subtotal + (p_subtotal * p_vat_rate / 100), 2);
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_role public.user_role; v_name text;
begin
  v_role := case when new.raw_user_meta_data->>'signup_role' in ('business', 'customer') then (new.raw_user_meta_data->>'signup_role')::public.user_role else 'customer'::public.user_role end;
  v_name := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(coalesce(new.email, new.phone, 'User'), '@', 1));
  insert into public.profiles(id, role, full_name, phone, email) values (new.id, v_role, v_name, new.phone, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

do $$ declare t text; begin
  foreach t in array array['profiles','businesses','customers','invoices','invoice_items','payments','transactions','kyc_submissions','reports','reviews','support_tickets','support_messages','subscriptions'] loop
    execute format('create trigger set_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

create or replace function public.prevent_immutable_change() returns trigger
language plpgsql set search_path = '' as $$ begin raise exception '% records are immutable', tg_table_name using errcode = '42501'; end; $$;
create trigger transactions_immutable before update or delete on public.transactions for each row execute function public.prevent_immutable_change();
create trigger transaction_events_immutable before update or delete on public.transaction_events for each row execute function public.prevent_immutable_change();
create trigger admin_actions_immutable before update or delete on public.admin_actions for each row execute function public.prevent_immutable_change();

create or replace function public.protect_profile_authorization() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.role, new.account_status) is distinct from (old.role, old.account_status) and not public.is_admin() then
    raise exception 'Only an admin can change role or account status' using errcode='42501';
  end if;
  return new;
end; $$;
create trigger protect_profile_authorization before update on public.profiles for each row execute function public.protect_profile_authorization();

create or replace function public.protect_business_verification() returns trigger
language plpgsql set search_path = '' as $$
begin
  if ((new.kyc_status,new.is_verified,new.subscription_status) is distinct from (old.kyc_status,old.is_verified,old.subscription_status)
      or ((new.rating,new.rating_count) is distinct from (old.rating,old.rating_count) and pg_trigger_depth() < 2))
     and not public.is_admin() then
    raise exception 'Protected business state cannot be changed directly' using errcode='42501';
  end if;
  return new;
end; $$;
create trigger protect_business_verification before update on public.businesses for each row execute function public.protect_business_verification();

create or replace function public.protect_customer_verification() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.kyc_status is distinct from old.kyc_status and not public.is_admin() then
    raise exception 'KYC state cannot be changed directly' using errcode='42501';
  end if;
  return new;
end; $$;
create trigger protect_customer_verification before update on public.customers for each row execute function public.protect_customer_verification();

create or replace function public.create_invoice(
  p_customer_id uuid, p_due_date date, p_items jsonb, p_vat_rate numeric default 0,
  p_payment_method text default 'fonepay_qr', p_notes text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_business public.businesses; v_invoice_id uuid; v_subtotal numeric; v_totals record;
begin
  select b.* into v_business from public.businesses b join public.profiles p on p.id=b.profile_id
  where b.profile_id=(select auth.uid()) and p.account_status='active';
  if not found then raise exception 'Active business profile required' using errcode='42501'; end if;
  if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found' using errcode='P0002'; end if;
  if p_due_date not between current_date and current_date + 7 then raise exception 'Due date must be between today and 7 days from today' using errcode='22023'; end if;
  if p_vat_rate < 0 or p_vat_rate > 100 then raise exception 'VAT rate must be between 0 and 100' using errcode='22023'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'Items must contain 1 to 100 entries' using errcode='22023'; end if;

  select round(sum(round(x.quantity*x.unit_price,2)),2) into v_subtotal
  from jsonb_to_recordset(p_items) as x(description text, category text, quantity numeric, unit_price numeric)
  where nullif(trim(x.description),'') is not null and x.quantity>0 and x.unit_price>=0;
  if v_subtotal is null or (select count(*) from jsonb_array_elements(p_items)) <> (select count(*) from jsonb_to_recordset(p_items) as x(description text, category text, quantity numeric, unit_price numeric) where nullif(trim(x.description),'') is not null and x.quantity>0 and x.unit_price>=0)
  then raise exception 'Each item needs a description, positive quantity, and non-negative unit price' using errcode='22023'; end if;
  select * into v_totals from public.calculate_invoice_totals(v_subtotal,p_vat_rate);

  insert into public.invoices(business_id,customer_id,due_date,payment_method,subtotal,vat_rate,vat_amount,total_amount,notes)
  values(v_business.id,p_customer_id,p_due_date,coalesce(nullif(trim(p_payment_method),''),'fonepay_qr'),v_totals.subtotal,p_vat_rate,v_totals.vat_amount,v_totals.total_amount,p_notes)
  returning id into v_invoice_id;
  insert into public.invoice_items(invoice_id,description,category,quantity,unit_price)
  select v_invoice_id,trim(x.description),nullif(trim(x.category),''),x.quantity,x.unit_price
  from jsonb_to_recordset(p_items) as x(description text, category text, quantity numeric, unit_price numeric);
  insert into public.transaction_events(invoice_id,actor_profile_id,event_type,new_status) values(v_invoice_id,(select auth.uid()),'invoice_created','sent');
  return v_invoice_id;
end; $$;

create or replace function public.mark_invoice_paid(p_invoice_id uuid, p_reference text default null, p_proof_path text default null, p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_invoice public.invoices; v_payment_id uuid;
begin
  select i.* into v_invoice from public.invoices i join public.customers c on c.id=i.customer_id
  where i.id=p_invoice_id and c.profile_id=(select auth.uid()) for update of i;
  if not found then raise exception 'Invoice not found or not owned by customer' using errcode='42501'; end if;
  if v_invoice.status not in ('sent','viewed','payment_rejected') then raise exception 'Invoice cannot be marked paid from status %',v_invoice.status using errcode='22023'; end if;
  if p_proof_path is not null and split_part(p_proof_path,'/',1) <> (select auth.uid())::text then raise exception 'Payment proof path must belong to the customer' using errcode='42501'; end if;
  insert into public.payments(invoice_id,customer_id,amount,payment_reference,proof_path,customer_note)
  values(v_invoice.id,v_invoice.customer_id,v_invoice.total_amount,nullif(trim(p_reference),''),nullif(trim(p_proof_path),''),p_note) returning id into v_payment_id;
  update public.invoices set status='verification_pending' where id=v_invoice.id;
  insert into public.transaction_events(invoice_id,actor_profile_id,event_type,previous_status,new_status,metadata)
  values(v_invoice.id,(select auth.uid()),'customer_marked_paid',v_invoice.status::text,'verification_pending',jsonb_build_object('payment_id',v_payment_id));
  return v_payment_id;
end; $$;

create or replace function public.admin_review_kyc(p_submission_id uuid, p_status public.kyc_status, p_comment text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_submission public.kyc_submissions;
begin
  if not public.is_admin() then raise exception 'Admin required' using errcode='42501'; end if;
  if p_status not in ('verified','rejected','additional_information_required') then raise exception 'Invalid review status' using errcode='22023'; end if;
  select * into v_submission from public.kyc_submissions where id=p_submission_id for update;
  if not found then raise exception 'KYC submission not found' using errcode='P0002'; end if;
  update public.kyc_submissions set status=p_status,reviewer_comment=p_comment,reviewed_by=(select auth.uid()),reviewed_at=now() where id=p_submission_id;
  if v_submission.subject_type='business' then
    update public.businesses set kyc_status=p_status,is_verified=(p_status='verified') where profile_id=v_submission.profile_id;
  else
    update public.customers set kyc_status=p_status where profile_id=v_submission.profile_id;
  end if;
  insert into public.admin_actions(admin_profile_id,target_profile_id,action,reason,metadata)
  values((select auth.uid()),v_submission.profile_id,'kyc_review',coalesce(p_comment,p_status::text),jsonb_build_object('submission_id',p_submission_id,'status',p_status));
end; $$;

create or replace function public.review_payment(p_payment_id uuid, p_confirmed boolean, p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_payment public.payments; v_invoice public.invoices; v_business public.businesses; v_customer public.customers; v_transaction_id uuid; v_snapshot jsonb;
begin
  select p.* into v_payment from public.payments p where p.id=p_payment_id for update;
  if not found or v_payment.status <> 'verification_pending' then raise exception 'Pending payment not found' using errcode='22023'; end if;
  select i.* into v_invoice from public.invoices i where i.id=v_payment.invoice_id for update;
  select b.* into v_business from public.businesses b where b.id=v_invoice.business_id and b.profile_id=(select auth.uid());
  if not found then raise exception 'Only the invoice business can review payment' using errcode='42501'; end if;
  select c.* into v_customer from public.customers c where c.id=v_invoice.customer_id;

  if not p_confirmed then
    update public.payments set status='rejected',business_note=p_note,verified_by=(select auth.uid()) where id=p_payment_id;
    update public.invoices set status='payment_rejected' where id=v_invoice.id;
    insert into public.transaction_events(invoice_id,actor_profile_id,event_type,previous_status,new_status,metadata)
    values(v_invoice.id,(select auth.uid()),'payment_rejected','verification_pending','payment_rejected',jsonb_build_object('payment_id',p_payment_id,'note',p_note));
    return null;
  end if;

  if v_payment.amount <> v_invoice.total_amount then raise exception 'Payment amount does not match invoice' using errcode='22023'; end if;
  update public.payments set status='verified',business_note=p_note,verified_at=now(),verified_by=(select auth.uid()) where id=p_payment_id;
  update public.invoices set status='paid' where id=v_invoice.id;
  v_snapshot := jsonb_build_object(
    'business',jsonb_build_object('name',v_business.business_name,'pan',v_business.pan_number,'address',v_business.address),
    'customer',jsonb_build_object('name',v_customer.full_name),
    'invoice_number',v_invoice.invoice_number,'issue_date',v_invoice.issue_date,'due_date',v_invoice.due_date,
    'items',(select jsonb_agg(jsonb_build_object('description',ii.description,'category',ii.category,'quantity',ii.quantity,'unit_price',ii.unit_price,'total',ii.line_total) order by ii.created_at,ii.id) from public.invoice_items ii where ii.invoice_id=v_invoice.id),
    'subtotal',v_invoice.subtotal,'vat_rate',v_invoice.vat_rate,'vat_amount',v_invoice.vat_amount,'total',v_invoice.total_amount,
    'payment',jsonb_build_object('reference',v_payment.payment_reference,'method',v_invoice.payment_method,'verified_at',now())
  );
  insert into public.transactions(transaction_number,invoice_id,payment_id,business_id,customer_id,subtotal,vat_rate,vat_amount,total_amount,payment_date,snapshot)
  values('TXN-'||replace(gen_random_uuid()::text,'-',''),v_invoice.id,p_payment_id,v_invoice.business_id,v_invoice.customer_id,v_invoice.subtotal,v_invoice.vat_rate,v_invoice.vat_amount,v_invoice.total_amount,now(),v_snapshot)
  returning id into v_transaction_id;
  insert into public.transaction_events(invoice_id,transaction_id,actor_profile_id,event_type,previous_status,new_status,metadata)
  values(v_invoice.id,v_transaction_id,(select auth.uid()),'payment_verified','verification_pending','paid',jsonb_build_object('payment_id',p_payment_id));
  return v_transaction_id;
end; $$;

create or replace function public.business_dashboard(p_business_id uuid) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare v_result jsonb;
begin
  if not (public.owns_business(p_business_id) or public.is_admin()) then raise exception 'Forbidden' using errcode='42501'; end if;
  select jsonb_build_object(
    'total_income',coalesce((select sum(total_amount) from public.transactions where business_id=p_business_id),0),
    'income_this_month',coalesce((select sum(total_amount) from public.transactions where business_id=p_business_id and payment_date>=date_trunc('month',now())),0),
    'pending_payments',(select count(*) from public.invoices where business_id=p_business_id and status in ('sent','viewed','verification_pending','payment_rejected') and due_date>=current_date),
    'outstanding_amount',coalesce((select sum(total_amount) from public.invoices where business_id=p_business_id and status not in ('paid','cancelled')),0),
    'overdue_payments',(select count(*) from public.invoices where business_id=p_business_id and status not in ('paid','cancelled') and due_date<current_date),
    'completed_transactions',(select count(*) from public.transactions where business_id=p_business_id),
    'customer_count',(select count(distinct customer_id) from public.transactions where business_id=p_business_id),
    'recent_transactions',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,transaction_number,total_amount,payment_date from public.transactions where business_id=p_business_id order by payment_date desc limit 10)x),'[]'::jsonb),
    'monthly_income',coalesce((select jsonb_agg(to_jsonb(x) order by month) from (select date_trunc('month',payment_date)::date month,sum(total_amount) amount from public.transactions where business_id=p_business_id group by 1 order by 1 desc limit 12)x),'[]'::jsonb),
    'category_income',coalesce((select jsonb_agg(to_jsonb(x) order by amount desc) from (select coalesce(item->>'category','Uncategorized') category,sum(((item->>'total')::numeric)) amount from public.transactions t cross join lateral jsonb_array_elements(t.snapshot->'items') item where t.business_id=p_business_id group by 1)x),'[]'::jsonb)
  ) into v_result; return v_result;
end; $$;

create or replace function public.customer_dashboard(p_customer_id uuid) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare v_result jsonb;
begin
  if not (public.owns_customer(p_customer_id) or public.is_admin()) then raise exception 'Forbidden' using errcode='42501'; end if;
  select jsonb_build_object(
    'total_expenses',coalesce((select sum(total_amount) from public.transactions where customer_id=p_customer_id),0),
    'expenses_this_month',coalesce((select sum(total_amount) from public.transactions where customer_id=p_customer_id and payment_date>=date_trunc('month',now())),0),
    'pending_payments',(select count(*) from public.invoices where customer_id=p_customer_id and status not in ('paid','cancelled')),
    'transaction_count',(select count(*) from public.transactions where customer_id=p_customer_id),
    'recent_transactions',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,transaction_number,total_amount,payment_date from public.transactions where customer_id=p_customer_id order by payment_date desc limit 10)x),'[]'::jsonb),
    'monthly_spending',coalesce((select jsonb_agg(to_jsonb(x) order by month) from (select date_trunc('month',payment_date)::date month,sum(total_amount) amount from public.transactions where customer_id=p_customer_id group by 1 order by 1 desc limit 12)x),'[]'::jsonb),
    'category_spending',coalesce((select jsonb_agg(to_jsonb(x) order by amount desc) from (select coalesce(item->>'category','Uncategorized') category,sum(((item->>'total')::numeric)) amount from public.transactions t cross join lateral jsonb_array_elements(t.snapshot->'items') item where t.customer_id=p_customer_id group by 1)x),'[]'::jsonb)
  ) into v_result; return v_result;
end; $$;

create or replace function public.effective_invoice_status(p_status public.invoice_status, p_due_date date)
returns text language sql stable set search_path='' as $$
  select case when p_status not in ('paid','cancelled') and p_due_date < current_date then 'overdue' else p_status::text end;
$$;

create view public.invoice_listing with (security_invoker=true) as
select i.*, public.effective_invoice_status(i.status,i.due_date) as effective_status
from public.invoices i;

create or replace function public.refresh_business_rating() returns trigger language plpgsql security definer set search_path='' as $$
declare v_id uuid:=coalesce(new.business_id,old.business_id);
begin update public.businesses b set rating=coalesce(x.avg_rating,0),rating_count=x.cnt from (select round(avg(rating)::numeric,2) avg_rating,count(*) cnt from public.reviews where business_id=v_id)x where b.id=v_id; return coalesce(new,old); end; $$;
create trigger refresh_rating after insert or update or delete on public.reviews for each row execute function public.refresh_business_rating();

-- Data API privileges are separate from row authorization.
grant usage on schema public to authenticated;
grant select on public.profiles,public.businesses,public.customers,public.invoices,public.invoice_items,public.payments,public.transactions,public.transaction_events,public.kyc_submissions,public.reports,public.reviews,public.support_tickets,public.support_messages,public.subscriptions to authenticated;
grant select on public.invoice_listing to authenticated;
grant insert,update on public.profiles,public.businesses,public.customers,public.kyc_submissions,public.reports,public.reviews,public.support_tickets,public.support_messages to authenticated;
revoke all on public.transactions,public.transaction_events,public.admin_actions from anon,authenticated;
grant select on public.transactions,public.transaction_events,public.admin_actions to authenticated;
revoke all on function public.create_invoice(uuid,date,jsonb,numeric,text,text),public.mark_invoice_paid(uuid,text,text,text),public.review_payment(uuid,boolean,text),public.business_dashboard(uuid),public.customer_dashboard(uuid) from public,anon;
grant execute on function public.create_invoice(uuid,date,jsonb,numeric,text,text),public.mark_invoice_paid(uuid,text,text,text),public.review_payment(uuid,boolean,text),public.business_dashboard(uuid),public.customer_dashboard(uuid) to authenticated;
revoke all on function public.handle_new_user(),public.refresh_business_rating(),public.admin_review_kyc(uuid,public.kyc_status,text) from public,anon;
grant execute on function public.admin_review_kyc(uuid,public.kyc_status,text) to authenticated;

do $$ declare t text; begin
  foreach t in array array['profiles','businesses','customers','invoices','invoice_items','payments','transactions','transaction_events','kyc_submissions','reports','reviews','support_tickets','support_messages','subscriptions','admin_actions'] loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

create policy profiles_select on public.profiles for select to authenticated using (id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.businesses b join public.invoices i on i.business_id=b.id join public.customers c on c.id=i.customer_id where (b.profile_id=(select auth.uid()) and c.profile_id=profiles.id) or (c.profile_id=(select auth.uid()) and b.profile_id=profiles.id)));
create policy profiles_update_self on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));
create policy profiles_update_admin on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy businesses_select_related on public.businesses for select to authenticated using (profile_id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.invoices i join public.customers c on c.id=i.customer_id where i.business_id=businesses.id and c.profile_id=(select auth.uid())));
create policy businesses_insert_owner on public.businesses for insert to authenticated with check (profile_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='business' and p.account_status='active'));
create policy businesses_update_owner on public.businesses for update to authenticated using (profile_id=(select auth.uid()) or public.is_admin()) with check (profile_id=(select auth.uid()) or public.is_admin());
create policy customers_select_related on public.customers for select to authenticated using (profile_id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.invoices i join public.businesses b on b.id=i.business_id where i.customer_id=customers.id and b.profile_id=(select auth.uid())));
create policy customers_insert_owner on public.customers for insert to authenticated with check (profile_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='customer' and p.account_status='active'));
create policy customers_update_owner on public.customers for update to authenticated using (profile_id=(select auth.uid()) or public.is_admin()) with check (profile_id=(select auth.uid()) or public.is_admin());
create policy invoices_select_party on public.invoices for select to authenticated using (public.is_admin() or public.owns_business(business_id) or public.owns_customer(customer_id));
create policy invoice_items_select_party on public.invoice_items for select to authenticated using (exists(select 1 from public.invoices i where i.id=invoice_id and (public.is_admin() or public.owns_business(i.business_id) or public.owns_customer(i.customer_id))));
create policy payments_select_party on public.payments for select to authenticated using (public.is_admin() or public.owns_customer(customer_id) or exists(select 1 from public.invoices i where i.id=invoice_id and public.owns_business(i.business_id)));
create policy transactions_select_party on public.transactions for select to authenticated using (public.is_admin() or public.owns_business(business_id) or public.owns_customer(customer_id));
create policy events_select_party on public.transaction_events for select to authenticated using (public.is_admin() or exists(select 1 from public.invoices i where i.id=invoice_id and (public.owns_business(i.business_id) or public.owns_customer(i.customer_id))));
create policy kyc_select_owner_admin on public.kyc_submissions for select to authenticated using (profile_id=(select auth.uid()) or public.is_admin());
create policy kyc_insert_owner on public.kyc_submissions for insert to authenticated with check (profile_id=(select auth.uid()) and subject_type in ('business','customer'));
create policy kyc_update_admin on public.kyc_submissions for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy reports_select_party_admin on public.reports for select to authenticated using (reporter_profile_id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.invoices i where i.id=invoice_id and public.owns_business(i.business_id)));
create policy reports_insert_party on public.reports for insert to authenticated with check (reporter_profile_id=(select auth.uid()) and exists(select 1 from public.invoices i where i.id=invoice_id and (public.owns_business(i.business_id) or public.owns_customer(i.customer_id))));
create policy reports_update_admin on public.reports for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy reviews_select_authenticated on public.reviews for select to authenticated using (true);
create policy reviews_insert_completed_customer on public.reviews for insert to authenticated with check (public.owns_customer(customer_id) and exists(select 1 from public.transactions t where t.id=transaction_id and t.customer_id=reviews.customer_id and t.business_id=reviews.business_id));
create policy reviews_update_owner on public.reviews for update to authenticated using (public.owns_customer(customer_id)) with check (public.owns_customer(customer_id));
create policy tickets_select_party on public.support_tickets for select to authenticated using (requester_profile_id=(select auth.uid()) or public.is_admin());
create policy tickets_insert_owner on public.support_tickets for insert to authenticated with check (requester_profile_id=(select auth.uid()));
create policy tickets_update_admin on public.support_tickets for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy messages_select_party on public.support_messages for select to authenticated using (public.is_admin() or (not is_internal and exists(select 1 from public.support_tickets t where t.id=ticket_id and t.requester_profile_id=(select auth.uid()))));
create policy messages_insert_party on public.support_messages for insert to authenticated with check (sender_profile_id=(select auth.uid()) and ((public.is_admin()) or (not is_internal and exists(select 1 from public.support_tickets t where t.id=ticket_id and t.requester_profile_id=(select auth.uid())))));
create policy subscriptions_select_owner_admin on public.subscriptions for select to authenticated using (public.is_admin() or public.owns_business(business_id));
create policy admin_actions_select_admin on public.admin_actions for select to authenticated using (public.is_admin());

-- All buckets are private. Paths start with the uploader's Auth UUID.
insert into storage.buckets(id,name,public,file_size_limit) values
('business-documents','business-documents',false,10485760),('customer-documents','customer-documents',false,10485760),
('kyc-documents','kyc-documents',false,10485760),('payment-proofs','payment-proofs',false,10485760),('payment-qr','payment-qr',false,5242880)
on conflict(id) do update set public=false;

create policy storage_owner_insert on storage.objects for insert to authenticated with check (bucket_id in ('business-documents','customer-documents','kyc-documents','payment-proofs','payment-qr') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy storage_owner_select on storage.objects for select to authenticated using (
  bucket_id in ('business-documents','customer-documents','kyc-documents','payment-proofs','payment-qr')
  and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or public.is_admin()
    or (bucket_id='payment-proofs' and exists(select 1 from public.payments p join public.invoices i on i.id=p.invoice_id join public.businesses b on b.id=i.business_id where p.proof_path=name and b.profile_id=(select auth.uid())))
    or (bucket_id='payment-qr' and exists(select 1 from public.businesses b join public.invoices i on i.business_id=b.id join public.customers c on c.id=i.customer_id where b.fonepay_qr_path=name and c.profile_id=(select auth.uid())))
  )
);
create policy storage_owner_update on storage.objects for update to authenticated using ((storage.foldername(name))[1]=(select auth.uid())::text) with check ((storage.foldername(name))[1]=(select auth.uid())::text);
create policy storage_owner_delete on storage.objects for delete to authenticated using ((storage.foldername(name))[1]=(select auth.uid())::text);

commit;
