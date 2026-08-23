alter table public.customer_profiles
  add column if not exists identity_document_type text,
  add column if not exists identity_document_number text;

alter table public.customer_profiles
  drop constraint if exists customer_profiles_identity_document_type_check;

alter table public.customer_profiles
  add constraint customer_profiles_identity_document_type_check
  check (
    identity_document_type is null
    or identity_document_type in ('citizenship', 'national_id', 'driving_licence', 'passport')
  );

create index if not exists customer_profiles_normalized_phone_idx
  on public.customer_profiles ((regexp_replace(phone_number, '[^0-9]', '', 'g')));

create or replace function public.lookup_customer_by_phone(p_phone text)
returns table (
  id uuid,
  full_name text,
  phone_number text,
  is_verified boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if normalized_phone like '977%' then
    normalized_phone := substring(normalized_phone from 4);
  end if;

  if not exists (
    select 1
    from public.users u
    join public.business_profiles b on b.id = u.id
    where u.id = auth.uid()
      and u.role = 'business'
      and u.is_active = true
  ) then
    raise exception 'Only active businesses can look up customers';
  end if;

  return query
  select c.id, u.full_name, c.phone_number, c.is_verified
  from public.customer_profiles c
  join public.users u on u.id = c.id
  where regexp_replace(c.phone_number, '[^0-9]', '', 'g') = normalized_phone
     or regexp_replace(c.phone_number, '[^0-9]', '', 'g') = '977' || normalized_phone
  limit 1;
end;
$$;

revoke all on function public.lookup_customer_by_phone(text) from public;
revoke all on function public.lookup_customer_by_phone(text) from anon;
grant execute on function public.lookup_customer_by_phone(text) to authenticated;

comment on function public.lookup_customer_by_phone(text) is
  'Returns minimal customer identity data for an authenticated active business using an exact normalized phone match.';
