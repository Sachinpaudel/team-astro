begin;

alter table public.businesses
  add column vat_registered boolean not null default false,
  add column vat_number text,
  add column default_vat_rate numeric(5,2) not null default 13.00
    check (default_vat_rate between 0 and 100),
  add constraint businesses_vat_registration_consistent check (
    (vat_registered and nullif(trim(vat_number),'') is not null)
    or (not vat_registered and vat_number is null)
  );

create unique index businesses_vat_number_unique
  on public.businesses(vat_number)
  where vat_number is not null;

alter table public.invoices
  add column is_vat_invoice boolean not null default false,
  add column seller_vat_number text;

create or replace function public.enforce_invoice_vat_registration()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_business public.businesses;
begin
  select * into v_business from public.businesses where id=new.business_id;
  if not found then raise exception 'Business not found' using errcode='23503'; end if;

  new.is_vat_invoice := v_business.vat_registered;
  if v_business.vat_registered then
    new.seller_vat_number := v_business.vat_number;
    new.vat_rate := v_business.default_vat_rate;
    new.vat_amount := round(new.subtotal * new.vat_rate / 100,2);
    new.total_amount := new.subtotal + new.vat_amount;
  else
    new.seller_vat_number := null;
    new.vat_rate := 0;
    new.vat_amount := 0;
    new.total_amount := new.subtotal;
  end if;
  return new;
end;
$$;

create trigger enforce_invoice_vat_registration
before insert on public.invoices
for each row execute function public.enforce_invoice_vat_registration();

-- VAT registration is verified business identity state, not a client-editable invoice option.
create or replace function public.protect_business_verification() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (
      (new.kyc_status,new.is_verified,new.subscription_status,new.vat_registered,new.vat_number,new.default_vat_rate)
      is distinct from
      (old.kyc_status,old.is_verified,old.subscription_status,old.vat_registered,old.vat_number,old.default_vat_rate)
      or ((new.rating,new.rating_count) is distinct from (old.rating,old.rating_count) and pg_trigger_depth() < 2)
    ) and not public.is_admin() then
    raise exception 'Protected business verification and tax state cannot be changed directly' using errcode='42501';
  end if;
  return new;
end;
$$;

comment on column public.businesses.vat_registered is 'Admin-verified VAT registration flag; determines whether invoices charge VAT.';
comment on column public.invoices.seller_vat_number is 'Historical seller VAT number copied at invoice creation; null for non-VAT invoices.';

commit;
