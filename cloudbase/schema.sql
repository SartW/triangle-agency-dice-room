-- Triangle Agency dice room schema for CloudBase PostgreSQL.
-- Run this file once in CloudBase / SQL database / SQL editor.

create extension if not exists pgcrypto;

create table if not exists public.dice_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
  name text not null default '分部外勤骰房',
  created_by text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.dice_room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.dice_rooms(id) on delete cascade,
  actor_token text not null,
  display_name text not null check (char_length(display_name) between 1 and 24),
  last_seen_at timestamptz not null default now(),
  unique (room_id, actor_token)
);

create table if not exists public.dice_public_rolls (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.dice_rooms(id) on delete cascade,
  actor_token text not null,
  display_name text not null,
  dice integer[] not null,
  three_count integer not null check (three_count between 0 and 6),
  created_at timestamptz not null default now()
);

create table if not exists public.dice_private_rolls (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.dice_rooms(id) on delete cascade,
  owner_token text not null,
  public_roll_id uuid references public.dice_public_rolls(id) on delete cascade,
  result integer not null,
  dice_expression text not null,
  results integer[] not null,
  label text not null,
  created_at timestamptz not null default now()
);

create index if not exists dice_public_rolls_room_created_idx
  on public.dice_public_rolls(room_id, created_at desc);
create index if not exists dice_private_rolls_room_owner_created_idx
  on public.dice_private_rolls(room_id, owner_token, created_at desc);
create index if not exists dice_room_members_seen_idx
  on public.dice_room_members(room_id, last_seen_at desc);

alter table public.dice_rooms enable row level security;
alter table public.dice_room_members enable row level security;
alter table public.dice_public_rolls enable row level security;
alter table public.dice_private_rolls enable row level security;

revoke all on public.dice_rooms from public;
revoke all on public.dice_room_members from public;
revoke all on public.dice_public_rolls from public;
revoke all on public.dice_private_rolls from public;

create or replace function public.dice_assert_request(p_actor_token text)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_claims jsonb;
  v_role text;
begin
  if p_actor_token is null or p_actor_token !~* '^[a-f0-9-]{36,64}$' then
    raise exception '终端身份无效';
  end if;

  begin
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  exception when others then
    v_claims := null;
  end;
  v_role := coalesce(v_claims ->> 'role', '');
  if v_claims is not null and v_role not in ('anon', 'authenticated') then
    raise exception '未授权的终端请求';
  end if;
end;
$$;

create or replace function public.dice_random_code()
returns text
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := gen_random_bytes(6);
  v_code text := '';
  i integer;
begin
  for i in 0..5 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % char_length(v_alphabet)) + 1, 1);
  end loop;
  return v_code;
end;
$$;

create or replace function public.dice_random_values(p_count integer, p_sides integer)
returns integer[]
language sql
volatile
security invoker
set search_path = pg_catalog, public
as $$
  select coalesce(array_agg(1 + floor(random() * p_sides)::integer), array[]::integer[])
  from generate_series(1, p_count);
$$;

create or replace function public.dice_create_room(
  p_actor_token text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_room public.dice_rooms%rowtype;
  v_code text;
  v_name text := left(btrim(coalesce(p_display_name, '')), 24);
  i integer;
begin
  perform public.dice_assert_request(p_actor_token);
  if v_name = '' then raise exception '请填写行动代号'; end if;

  for i in 1..8 loop
    v_code := public.dice_random_code();
    exit when not exists (select 1 from public.dice_rooms where code = v_code);
  end loop;

  insert into public.dice_rooms(code, created_by)
  values (v_code, p_actor_token)
  returning * into v_room;

  insert into public.dice_room_members(room_id, actor_token, display_name)
  values (v_room.id, p_actor_token, v_name);

  return jsonb_build_object('room', jsonb_build_object('code', v_room.code, 'name', v_room.name));
end;
$$;

create or replace function public.dice_join_room(
  p_actor_token text,
  p_code text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_room public.dice_rooms%rowtype;
  v_name text := left(btrim(coalesce(p_display_name, '')), 24);
begin
  perform public.dice_assert_request(p_actor_token);
  if v_name = '' then raise exception '请填写行动代号'; end if;

  select * into v_room from public.dice_rooms where code = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception '未找到该骰房'; end if;

  insert into public.dice_room_members(room_id, actor_token, display_name, last_seen_at)
  values (v_room.id, p_actor_token, v_name, now())
  on conflict (room_id, actor_token)
  do update set display_name = excluded.display_name, last_seen_at = excluded.last_seen_at;

  return jsonb_build_object('room', jsonb_build_object('code', v_room.code, 'name', v_room.name));
end;
$$;

create or replace function public.dice_get_room(
  p_actor_token text,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_room public.dice_rooms%rowtype;
  v_is_member boolean;
begin
  perform public.dice_assert_request(p_actor_token);
  select * into v_room from public.dice_rooms where code = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception '骰房不存在'; end if;

  select exists(
    select 1 from public.dice_room_members
    where room_id = v_room.id and actor_token = p_actor_token
  ) into v_is_member;
  if not v_is_member then raise exception '请先加入骰房'; end if;

  update public.dice_room_members
  set last_seen_at = now()
  where room_id = v_room.id and actor_token = p_actor_token;

  return jsonb_build_object(
    'room', jsonb_build_object('code', v_room.code, 'name', v_room.name),
    'rolls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'displayName', r.display_name,
        'dice', r.dice,
        'threeCount', r.three_count,
        'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.dice_public_rolls
        where room_id = v_room.id
        order by created_at desc
        limit 40
      ) r
    ), '[]'::jsonb),
    'privateRolls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'publicRollId', r.public_roll_id,
        'result', r.result,
        'diceExpression', r.dice_expression,
        'results', r.results,
        'label', r.label,
        'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.dice_private_rolls
        where room_id = v_room.id and owner_token = p_actor_token
        order by created_at desc
        limit 40
      ) r
    ), '[]'::jsonb),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('displayName', m.display_name) order by m.display_name)
      from public.dice_room_members m
      where m.room_id = v_room.id and m.last_seen_at >= now() - interval '2 minutes'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.dice_roll(
  p_actor_token text,
  p_code text,
  p_mode text default 'public',
  p_include_correction boolean default false,
  p_secret_count integer default 1,
  p_secret_sides integer default 8,
  p_secret_label text default '修正'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_room public.dice_rooms%rowtype;
  v_member public.dice_room_members%rowtype;
  v_public public.dice_public_rolls%rowtype;
  v_private public.dice_private_rolls%rowtype;
  v_dice integer[];
  v_secret integer[];
  v_count integer := greatest(1, least(6, coalesce(p_secret_count, 1)));
  v_sides integer := greatest(2, least(100, coalesce(p_secret_sides, 8)));
  v_label text := left(coalesce(nullif(btrim(p_secret_label), ''), '修正'), 16);
begin
  perform public.dice_assert_request(p_actor_token);
  select * into v_room from public.dice_rooms where code = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception '骰房不存在'; end if;

  select * into v_member from public.dice_room_members
  where room_id = v_room.id and actor_token = p_actor_token;
  if not found then raise exception '请先加入骰房'; end if;

  update public.dice_room_members set last_seen_at = now() where id = v_member.id;

  if p_mode = 'secret' then
    v_secret := public.dice_random_values(v_count, v_sides);
    insert into public.dice_private_rolls(
      room_id, owner_token, result, dice_expression, results, label
    ) values (
      v_room.id, p_actor_token,
      (select sum(value) from unnest(v_secret) value),
      v_count || 'D' || v_sides,
      v_secret, v_label
    ) returning * into v_private;

    return jsonb_build_object('privateRoll', jsonb_build_object(
      'id', v_private.id,
      'result', v_private.result,
      'diceExpression', v_private.dice_expression,
      'results', v_private.results,
      'label', v_private.label,
      'createdAt', v_private.created_at
    ));
  end if;

  if p_mode <> 'public' then raise exception '未知的投骰方式'; end if;
  v_dice := public.dice_random_values(6, 4);
  insert into public.dice_public_rolls(
    room_id, actor_token, display_name, dice, three_count
  ) values (
    v_room.id, p_actor_token, v_member.display_name, v_dice,
    (select count(*) from unnest(v_dice) value where value = 3)
  ) returning * into v_public;

  if coalesce(p_include_correction, false) then
    v_secret := public.dice_random_values(v_count, v_sides);
    insert into public.dice_private_rolls(
      room_id, owner_token, public_roll_id, result, dice_expression, results, label
    ) values (
      v_room.id, p_actor_token, v_public.id,
      (select sum(value) from unnest(v_secret) value),
      v_count || 'D' || v_sides,
      v_secret, v_label
    ) returning * into v_private;
  end if;

  return jsonb_build_object(
    'roll', jsonb_build_object(
      'id', v_public.id,
      'displayName', v_public.display_name,
      'dice', v_public.dice,
      'threeCount', v_public.three_count,
      'createdAt', v_public.created_at
    ),
    'privateRoll', case when v_private.id is null then null else jsonb_build_object(
      'id', v_private.id,
      'result', v_private.result,
      'diceExpression', v_private.dice_expression,
      'results', v_private.results,
      'label', v_private.label,
      'createdAt', v_private.created_at
    ) end
  );
end;
$$;

comment on function public.dice_create_room(text, text) is 'Create a Triangle Agency dice room.';
comment on function public.dice_join_room(text, text, text) is 'Join a dice room by room code.';
comment on function public.dice_get_room(text, text) is 'Read public rolls and only the current device private rolls.';
comment on function public.dice_roll(text, text, text, boolean, integer, integer, text) is 'Generate public or private dice on PostgreSQL.';
