-- =====================================================================
-- Sameh & Mazen — database setup
-- How to use: Supabase → SQL Editor → New query → paste ALL of this → Run.
-- BEFORE you run it: change the barber email below (line with 'CHANGE-ME').
-- =====================================================================

-- ---------- tables ----------
create table if not exists public.barbers (
  email text primary key
);

create table if not exists public.customers (
  id            uuid primary key default gen_random_uuid(),
  code          text unique not null,          -- shown on the card and in the QR, e.g. OMAR-4821
  token         text unique not null,          -- secret part of the customer's own card link
  name          text not null,
  phone         text unique not null,
  birthday      date,
  referred_by   text,                          -- code of the friend who invited them
  stamps        int  not null default 0,
  lifetime      int  not null default 0,
  used          int[] not null default '{}',   -- prizes already given on this card (3,5,7,10)
  last_visit    date,
  streak        int  not null default 0,
  badges        text[] not null default '{}',
  pending_wheel boolean not null default false,
  wheel_prize   text,
  created_at    timestamptz not null default now()
);

create table if not exists public.logs (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  customer    text,
  kind        text not null,
  detail      text
);

create table if not exists public.gifts (
  code        text primary key,
  service     text not null,
  to_name     text,
  from_name   text,
  message     text,
  active      boolean not null default false,
  used        boolean not null default false,
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);

-- Nobody can touch the tables directly. Everything goes through the functions below.
alter table public.barbers   enable row level security;
alter table public.customers enable row level security;
alter table public.logs      enable row level security;
alter table public.gifts     enable row level security;

-- ---------- helpers ----------
create or replace function public.is_barber() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from barbers where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

create or replace function public.cairo_today() returns date
language sql stable as $$ select (now() at time zone 'Africa/Cairo')::date $$;

create or replace function public.rand_code(n int) returns text
language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random()*32)+1)::int, 1), '')
  from generate_series(1, n)
$$;

create or replace function public.card_json(c customers) returns json
language sql stable as $$
  select json_build_object(
    'code', c.code, 'name', c.name, 'birthday', c.birthday, 'stamps', c.stamps, 'lifetime', c.lifetime,
    'used', c.used, 'last_visit', c.last_visit, 'streak', c.streak, 'badges', c.badges,
    'pending_wheel', c.pending_wheel, 'wheel_prize', c.wheel_prize)
$$;

-- ---------- customer functions (anyone with the website) ----------
create or replace function public.join_club(p_name text, p_phone text, p_birthday date default null, p_friend text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  nm text := btrim(coalesce(p_name, ''));
  c customers;
  base text;
begin
  if length(nm) < 2 or length(nm) > 40 then raise exception 'Please write your name.'; end if;
  if length(ph) < 10 or length(ph) > 15 then raise exception 'Please write a correct phone number.'; end if;
  select * into c from customers where phone = ph;
  if found then
    return json_build_object('token', c.token, 'existing', true);
  end if;
  base := upper(regexp_replace(split_part(nm, ' ', 1), '[^A-Za-z]', '', 'g'));
  if base = '' then base := 'SM'; end if;
  base := left(base, 8);
  insert into customers (code, token, name, phone, birthday, referred_by)
  values (base || '-' || (1000 + floor(random()*9000))::int, rand_code(24), nm, ph, p_birthday,
          nullif(upper(btrim(coalesce(p_friend, ''))), ''))
  returning * into c;
  insert into logs (customer, kind, detail) values (c.code, 'join', c.name);
  return json_build_object('token', c.token, 'existing', false);
end $$;

create or replace function public.get_card(p_token text) returns json
language plpgsql stable security definer set search_path = public as $$
declare c customers;
begin
  select * into c from customers where token = p_token;
  if not found then return null; end if;
  return card_json(c);
end $$;

create or replace function public.set_birthday(p_token text, p_birthday date) returns void
language sql security definer set search_path = public as $$
  update customers set birthday = p_birthday where token = p_token;
$$;

create or replace function public.create_gift(p_service text, p_to text, p_from text, p_message text) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  if p_service not in ('Haircut','Cut + beard','Groom package') then raise exception 'Unknown gift.'; end if;
  k := 'GIFT-' || rand_code(5);
  insert into gifts (code, service, to_name, from_name, message)
  values (k, p_service, left(p_to, 40), left(p_from, 40), left(p_message, 200));
  return k;
end $$;

create or replace function public.check_gift(p_code text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('service', service, 'from_name', from_name, 'to_name', to_name, 'active', active, 'used', used)
  from gifts where code = upper(btrim(p_code));
$$;

-- ---------- barber functions (only logged-in barbers) ----------
create or replace function public.b_check() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_barber() then raise exception 'Barber login needed.'; end if;
end $$;

create or replace function public.b_customers(p_search text default '') returns setof json
language plpgsql stable security definer set search_path = public as $$
declare q text := '%' || lower(btrim(coalesce(p_search, ''))) || '%';
begin
  perform b_check();
  return query
    select json_build_object('code', c.code, 'name', c.name, 'phone', c.phone, 'stamps', c.stamps, 'lifetime', c.lifetime,
      'used', c.used, 'last_visit', c.last_visit, 'streak', c.streak, 'badges', c.badges,
      'pending_wheel', c.pending_wheel, 'wheel_prize', c.wheel_prize, 'referred_by', c.referred_by)
    from customers c
    where lower(c.code) like q or lower(c.name) like q or c.phone like q
    order by c.last_visit desc nulls last, c.created_at desc
    limit 50;
end $$;

create or replace function public.b_add_stamp(p_code text, p_bonus text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  c customers; t date := cairo_today(); n int := 1; dow int; gap int; ref customers;
begin
  perform b_check();
  select * into c from customers where code = upper(btrim(p_code)) for update;
  if not found then raise exception 'No customer with this code.'; end if;

  if p_bonus is null then
    if c.last_visit = t then raise exception 'This customer already got a stamp today.'; end if;
    dow := extract(dow from t);
    if dow in (2, 3) then n := 2; end if;                                         -- Tuesday / Wednesday
    if c.birthday is not null and extract(month from c.birthday) = extract(month from t) then n := 2; end if;
    gap := case when c.last_visit is null then null else t - c.last_visit end;
    c.streak := case when gap is not null and gap <= 21 then c.streak + 1 else 1 end;
    c.last_visit := t;
    c.lifetime := c.lifetime + 1;
    if not ('first' = any(c.badges)) then c.badges := array_append(c.badges, 'first'); end if;
    if dow in (2, 3) and not ('weekday' = any(c.badges)) then c.badges := array_append(c.badges, 'weekday'); end if;
    if c.streak >= 3 and not ('streak' = any(c.badges)) then c.badges := array_append(c.badges, 'streak'); end if;
    if c.lifetime >= 25 and not ('gold' = any(c.badges)) then c.badges := array_append(c.badges, 'gold'); end if;
    if n = 2 and c.birthday is not null and extract(month from c.birthday) = extract(month from t)
       and not ('bday' = any(c.badges)) then c.badges := array_append(c.badges, 'bday'); end if;
    -- first visit of an invited friend: the friend who invited gets 1 bonus stamp
    if c.lifetime = 1 and c.referred_by is not null then
      select * into ref from customers where code = c.referred_by for update;
      if found then
        update customers set stamps = least(10, stamps + 1),
          badges = case when 'brother' = any(badges) then badges else array_append(badges, 'brother') end
        where id = ref.id;
        insert into logs (customer, kind, detail) values (ref.code, 'referral', 'friend ' || c.name || ' came');
      end if;
    end if;
  end if;

  if c.stamps < 7 and c.stamps + n >= 7 and not (7 = any(c.used)) then c.pending_wheel := true; end if;
  c.stamps := least(10, c.stamps + n);

  update customers set stamps = c.stamps, lifetime = c.lifetime, last_visit = c.last_visit, streak = c.streak,
    badges = c.badges, pending_wheel = c.pending_wheel where id = c.id;
  insert into logs (customer, kind, detail) values (c.code, case when p_bonus is null then 'stamp' else 'bonus' end,
    '+' || n || coalesce(' (' || p_bonus || ')', '') || ' → ' || c.stamps || '/10');
  return card_json(c);
end $$;

create or replace function public.b_give_reward(p_code text, p_n int) returns json
language plpgsql security definer set search_path = public as $$
declare c customers;
begin
  perform b_check();
  select * into c from customers where code = upper(btrim(p_code)) for update;
  if not found then raise exception 'No customer with this code.'; end if;
  if p_n not in (3, 5, 10) or c.stamps < p_n or p_n = any(c.used) then raise exception 'This prize is not ready.'; end if;
  if p_n = 10 then
    c.stamps := 0; c.used := '{}'; c.pending_wheel := false;
  else
    c.used := array_append(c.used, p_n);
  end if;
  update customers set stamps = c.stamps, used = c.used, pending_wheel = c.pending_wheel where id = c.id;
  insert into logs (customer, kind, detail) values (c.code, 'prize', 'prize at ' || p_n || ' given');
  return card_json(c);
end $$;

create or replace function public.b_spin(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare c customers; prizes text[] := array['Free eyebrow shaping','Double stamp next visit','Free hair wax','Free hot towel shave','20% off next cut','Free beard oil sample']; i int;
begin
  perform b_check();
  select * into c from customers where code = upper(btrim(p_code)) for update;
  if not found or not c.pending_wheel then raise exception 'The wheel is not ready for this customer.'; end if;
  i := floor(random() * 6)::int;
  update customers set pending_wheel = false, used = array_append(used, 7), wheel_prize = prizes[i + 1],
    badges = case when 'wheel' = any(badges) then badges else array_append(badges, 'wheel') end
  where id = c.id;
  insert into logs (customer, kind, detail) values (c.code, 'wheel', prizes[i + 1]);
  return json_build_object('index', i, 'prize', prizes[i + 1]);
end $$;

create or replace function public.b_wheel_given(p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform b_check();
  insert into logs (customer, kind, detail) select code, 'wheel-given', wheel_prize from customers where code = upper(btrim(p_code));
  update customers set wheel_prize = null where code = upper(btrim(p_code));
end $$;

create or replace function public.b_gifts() returns setof gifts
language plpgsql stable security definer set search_path = public as $$
begin
  perform b_check();
  return query select * from gifts order by created_at desc limit 50;
end $$;

create or replace function public.b_gift_activate(p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform b_check();
  update gifts set active = true where code = upper(btrim(p_code)) and not used;
  insert into logs (customer, kind, detail) values (null, 'gift-paid', upper(btrim(p_code)));
end $$;

create or replace function public.b_gift_use(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare g gifts;
begin
  perform b_check();
  select * into g from gifts where code = upper(btrim(p_code)) for update;
  if not found then raise exception 'Code not found. Check the letters.'; end if;
  if g.used then raise exception 'This code was already used.'; end if;
  if not g.active then raise exception 'Not paid yet. Take the money first, then tap "Paid, turn on".'; end if;
  update gifts set used = true, used_at = now() where code = g.code;
  insert into logs (customer, kind, detail) values (null, 'gift-used', g.code || ' · ' || g.service || ' for ' || coalesce(g.to_name, ''));
  return json_build_object('service', g.service, 'to_name', g.to_name);
end $$;

create or replace function public.b_today() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform b_check();
  return json_build_object(
    'stamps',   (select count(*) from logs where kind = 'stamp' and (at at time zone 'Africa/Cairo')::date = cairo_today()),
    'prizes',   (select count(*) from logs where kind in ('prize','wheel','gift-used') and (at at time zone 'Africa/Cairo')::date = cairo_today()),
    'members',  (select count(*) from customers),
    'log',      (select coalesce(json_agg(l), '[]') from (select at, customer, kind, detail from logs order by at desc limit 30) l));
end $$;

-- Who may call what
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.join_club(text, text, date, text), public.get_card(text), public.set_birthday(text, date),
  public.create_gift(text, text, text, text), public.check_gift(text) to anon, authenticated;
grant execute on function public.is_barber(), public.b_customers(text), public.b_add_stamp(text, text), public.b_give_reward(text, int),
  public.b_spin(text), public.b_wheel_given(text), public.b_gifts(), public.b_gift_activate(text), public.b_gift_use(text),
  public.b_today() to authenticated;

-- ---------- the barber ----------
-- Write the email the barber will log in with (make the same user in Authentication → Users → Add user).
insert into public.barbers (email) values ('CHANGE-ME@example.com') on conflict do nothing;
