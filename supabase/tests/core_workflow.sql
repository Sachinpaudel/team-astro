begin;
select plan(19);

-- Supabase local test helpers: emulate authenticated JWTs with request.jwt.claims.
insert into auth.users(id,email,raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000001','business@example.test','{"signup_role":"business","full_name":"Test Business"}'),
  ('20000000-0000-0000-0000-000000000002','customer@example.test','{"signup_role":"customer","full_name":"Test Customer"}'),
  ('30000000-0000-0000-0000-000000000003','nonvat@example.test','{"signup_role":"business","full_name":"Non VAT Business"}');

select is((select role::text from public.profiles where id='10000000-0000-0000-0000-000000000001'),'business','signup trigger creates business profile');
select is((select role::text from public.profiles where id='20000000-0000-0000-0000-000000000002'),'customer','signup trigger creates customer profile');

insert into public.businesses(id,profile_id,business_name,pan_number,owner_contact_name,phone,address,business_type,vat_registered,vat_number)
values('11000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Repair Sathi','PAN12345','Owner','9800000001','Kathmandu','repair_service',true,'VAT12345');
insert into public.customers(id,profile_id,full_name,phone)
values('22000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Test Customer','9800000002');
insert into public.businesses(id,profile_id,business_name,pan_number,owner_contact_name,phone,address,business_type)
values('33000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000003','Non VAT Sathi','PAN54321','Owner','9800000003','Lalitpur','service_provider');
insert into public.invoices(business_id,customer_id,due_date,subtotal,vat_rate,vat_amount,total_amount)
values('33000000-0000-0000-0000-000000000003','22000000-0000-0000-0000-000000000002',current_date+1,100,13,13,113);
select is((select is_vat_invoice from public.invoices where business_id='33000000-0000-0000-0000-000000000003'),false,'non-VAT seller creates non-VAT invoice');
select is((select vat_amount from public.invoices where business_id='33000000-0000-0000-0000-000000000003'),0::numeric,'non-VAT seller cannot charge VAT');
select is((select total_amount from public.invoices where business_id='33000000-0000-0000-0000-000000000003'),100::numeric,'non-VAT total excludes VAT');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);

select throws_ok(
  $$select public.create_invoice('22000000-0000-0000-0000-000000000002',current_date+8,'[{"description":"Repair","quantity":1,"unit_price":1000}]',13,'fonepay_qr',null)$$,
  '22023','Due date must be between today and 7 days from today','rejects due dates beyond seven days');

select lives_ok(
  $$select public.create_invoice('22000000-0000-0000-0000-000000000002',current_date+3,'[{"description":"Repair","category":"Service","quantity":2,"unit_price":500},{"description":"Part","category":"Parts","quantity":1,"unit_price":250}]',13,'fonepay_qr','Thanks')$$,
  'creates a validated invoice');

select is((select subtotal from public.invoices where business_id='11000000-0000-0000-0000-000000000001'),1250.00::numeric,'subtotal is server-calculated');
select is((select vat_amount from public.invoices where business_id='11000000-0000-0000-0000-000000000001'),162.50::numeric,'VAT is server-calculated');
select is((select total_amount from public.invoices where business_id='11000000-0000-0000-0000-000000000001'),1412.50::numeric,'total is server-calculated');
select is((select count(*)::int from public.invoice_items),2,'all items created');
select is((select count(*)::int from public.transaction_events where event_type='invoice_created'),1,'creation audit event exists');

select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select lives_ok($$select public.mark_invoice_paid((select id from public.invoices where business_id='11000000-0000-0000-0000-000000000001'),'REF-1',null,'Paid externally')$$,'customer marks paid');
select is((select status::text from public.invoices where business_id='11000000-0000-0000-0000-000000000001'),'verification_pending','invoice awaits verification');

select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.review_payment((select id from public.payments limit 1),true,'Received')$$,'business verifies payment');
select is((select status::text from public.invoices where business_id='11000000-0000-0000-0000-000000000001'),'paid','invoice becomes paid');
select is((select count(*)::int from public.transactions),1,'one immutable final transaction created');
select is((select snapshot->'business'->>'name' from public.transactions limit 1),'Repair Sathi','snapshot preserves business name');
select throws_ok($$update public.transactions set total_amount=1$$,'42501','transactions records are immutable','final bill cannot be edited');

select * from finish();
rollback;
