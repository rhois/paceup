-- ============================================================================
--  PaceUp — Skema database (PostgreSQL 15 / Supabase)
-- ============================================================================
--  Cara pakai:
--    1. Buka Supabase Dashboard -> SQL Editor.
--    2. Jalankan file ini (schema.sql).
--    3. Lanjutkan dengan rls.sql, lalu functions.sql, terakhir seed.sql.
--
--  Catatan: semua koordinat disimpan sebagai NUMERIC (bukan PostGIS) supaya
--  proyek bisa langsung jalan di Supabase free tier. Bila PostGIS tersedia,
--  lihat bagian OPSIONAL di bawah untuk kolom geometry + index GiST.
-- ============================================================================

create extension if not exists "pgcrypto";  -- gen_random_uuid()
-- create extension if not exists postgis;  -- opsional, lihat bagian OPSIONAL

-- ---------------------------------------------------------------------------
-- ENUM
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'activity_type') then
    create type activity_type as enum ('run', 'trailRun', 'walk', 'hike', 'ride');
  end if;
  if not exists (select 1 from pg_type where typname = 'visibility') then
    create type visibility as enum ('everyone', 'followers', 'only_me');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- profiles
--   Satu baris per pengguna. Dibuat otomatis oleh trigger handle_new_user().
--   Statistik agregat (activity_count, total_distance_meters, ...) di-cache di
--   sini agar feed & leaderboard tidak perlu menjumlahkan seluruh tabel.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id                       uuid primary key references auth.users (id) on delete cascade,
  username                 text not null unique,
  display_name             text not null default '',
  avatar_url               text,
  bio                      text not null default '',
  city                     text not null default '',
  weight_kg                numeric(5, 2) not null default 65 check (weight_kg > 0 and weight_kg < 400),
  height_cm                numeric(5, 2) not null default 170 check (height_cm > 0 and height_cm < 300),
  is_private               boolean not null default false,
  follower_count           integer not null default 0,
  following_count          integer not null default 0,
  activity_count           integer not null default 0,
  total_distance_meters    double precision not null default 0,
  total_elevation_meters   double precision not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint username_format check (username ~ '^[A-Za-z0-9._]{3,30}$')
);

create index if not exists profiles_username_idx
  on public.profiles (lower(username));
create index if not exists profiles_total_distance_idx
  on public.profiles (total_distance_meters desc);

-- ---------------------------------------------------------------------------
-- activities
--   Ringkasan satu aktivitas. Titik GPS detail ada di activity_points.
-- ---------------------------------------------------------------------------
create table if not exists public.activities (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profiles (id) on delete cascade,
  type                  activity_type not null default 'run',
  title                 text not null default '',
  description           text not null default '',
  started_at            timestamptz not null,
  distance_meters       double precision not null default 0 check (distance_meters >= 0),
  moving_seconds        integer not null default 0 check (moving_seconds >= 0),
  elapsed_seconds       integer not null default 0 check (elapsed_seconds >= 0),
  elevation_gain        double precision not null default 0,
  elevation_loss        double precision not null default 0,
  avg_pace_sec_per_km   double precision not null default 0,
  max_speed_kmh         double precision not null default 0,
  avg_heart_rate        integer not null default 0,
  avg_cadence_spm       integer not null default 0,
  calories              integer not null default 0,
  kudos_count           integer not null default 0,
  comment_count         integer not null default 0,
  visibility            visibility not null default 'followers',

  -- Bounding box rute, dipakai untuk filter "aktivitas di sekitar sini".
  start_lat             double precision,
  start_lon             double precision,
  end_lat               double precision,
  end_lon               double precision,

  -- Encoded polyline (presisi 5) untuk render peta tanpa menarik semua titik.
  map_polyline          text not null default '',

  -- Cache local timezone pengguna: memudahkan grouping harian/mingguan.
  timezone              text not null default 'Asia/Jakarta',

  achievements          text[] not null default '{}',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint elapsed_gte_moving check (elapsed_seconds >= moving_seconds - 5)
);

create index if not exists activities_user_started_idx
  on public.activities (user_id, started_at desc);
create index if not exists activities_started_idx
  on public.activities (started_at desc);
create index if not exists activities_user_distance_idx
  on public.activities (user_id, distance_meters desc);
create index if not exists activities_visibility_idx
  on public.activities (visibility);

-- Untuk filter geografis sederhana (tanpa PostGIS).
create index if not exists activities_start_latlon_idx
  on public.activities (start_lat, start_lon)
  where start_lat is not null;

-- ---------------------------------------------------------------------------
-- activity_points
--   Track GPS mentah. Satu aktivitas bisa punya ribuan baris.
--   `seq` menjaga urutan (penting: timestamptz bisa tie pada perangkat tertentu).
-- ---------------------------------------------------------------------------
create table if not exists public.activity_points (
  id                bigserial primary key,
  activity_id       uuid not null references public.activities (id) on delete cascade,
  seq               integer not null,
  lat               double precision not null check (lat between -90 and 90),
  lon               double precision not null check (lon between -180 and 180),
  recorded_at       timestamptz not null,
  altitude          double precision not null default 0,
  speed_mps         double precision not null default 0 check (speed_mps >= 0),
  distance_delta    double precision not null default 0,
  accuracy          double precision not null default 0,
  cadence           integer not null default 0,
  heart_rate        integer not null default 0,
  paused            boolean not null default false,

  unique (activity_id, seq)
);

create index if not exists activity_points_activity_seq_idx
  on public.activity_points (activity_id, seq);

-- ---------------------------------------------------------------------------
-- kudos
-- ---------------------------------------------------------------------------
create table if not exists public.kudos (
  activity_id  uuid not null references public.activities (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (activity_id, user_id)
);

create index if not exists kudos_user_idx on public.kudos (user_id);

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
create table if not exists public.comments (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references public.activities (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  body         text not null check (char_length(trim(body)) between 1 and 1000),
  created_at   timestamptz not null default now()
);

create index if not exists comments_activity_created_idx
  on public.comments (activity_id, created_at);

-- ---------------------------------------------------------------------------
-- follows
-- ---------------------------------------------------------------------------
create table if not exists public.follows (
  follower_id   uuid not null references public.profiles (id) on delete cascade,
  following_id  uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint no_self_follow check (follower_id <> following_id)
);

create index if not exists follows_following_idx on public.follows (following_id);

-- ---------------------------------------------------------------------------
-- TRIGGERS: timestamps, counter cache, dan pembuatan profil otomatis
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists activities_touch on public.activities;
create trigger activities_touch
  before update on public.activities
  for each row execute function public.touch_updated_at();

-- Profil otomatis saat pengguna baru mendaftar lewat Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_username text;
  final_username text;
  suffix int := 0;
begin
  base_username := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
    split_part(new.email, '@', 1)
  );
  -- Bersihkan agar lolos constraint username_format.
  base_username := regexp_replace(lower(base_username), '[^a-z0-9._]', '', 'g');
  if char_length(base_username) < 3 then
    base_username := 'runner' || substr(replace(new.id::text, '-', ''), 1, 6);
  end if;

  final_username := base_username;
  while exists (select 1 from public.profiles where username = final_username) loop
    suffix := suffix + 1;
    final_username := base_username || suffix::text;
  end loop;

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    final_username,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), final_username)
  )
  on conflict (id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Kudos counter.
create or replace function public.sync_kudos_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.activities
      set kudos_count = kudos_count + 1
      where id = new.activity_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.activities
      set kudos_count = greatest(kudos_count - 1, 0)
      where id = old.activity_id;
    return old;
  end if;
  return null;
end $$;

drop trigger if exists kudos_count_trigger on public.kudos;
create trigger kudos_count_trigger
  after insert or delete on public.kudos
  for each row execute function public.sync_kudos_count();

-- Komentar counter.
create or replace function public.sync_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.activities
      set comment_count = comment_count + 1
      where id = new.activity_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.activities
      set comment_count = greatest(comment_count - 1, 0)
      where id = old.activity_id;
    return old;
  end if;
  return null;
end $$;

drop trigger if exists comment_count_trigger on public.comments;
create trigger comment_count_trigger
  after insert or delete on public.comments
  for each row execute function public.sync_comment_count();

-- Statistik profil: diperbarui saat aktivitas dibuat/diubah/dihapus.
create or replace function public.refresh_profile_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  target := coalesce(new.user_id, old.user_id);

  update public.profiles p
     set activity_count         = agg.cnt,
         total_distance_meters  = agg.dist,
         total_elevation_meters = agg.elev
    from (
      select count(*)::int                as cnt,
             coalesce(sum(distance_meters), 0) as dist,
             coalesce(sum(elevation_gain), 0)  as elev
        from public.activities
       where user_id = target
    ) agg
   where p.id = target;

  return null;
end $$;

drop trigger if exists activities_stats_trigger on public.activities;
create trigger activities_stats_trigger
  after insert or update of distance_meters, elevation_gain or delete
  on public.activities
  for each row execute function public.refresh_profile_stats();

-- Follower counter.
create or replace function public.sync_follow_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set follower_count = follower_count + 1
      where id = new.following_id;
    update public.profiles set following_count = following_count + 1
      where id = new.follower_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles set follower_count = greatest(follower_count - 1, 0)
      where id = old.following_id;
    update public.profiles set following_count = greatest(following_count - 1, 0)
      where id = old.follower_id;
    return old;
  end if;
  return null;
end $$;

drop trigger if exists follows_count_trigger on public.follows;
create trigger follows_count_trigger
  after insert or delete on public.follows
  for each row execute function public.sync_follow_counts();

-- ---------------------------------------------------------------------------
-- FUNGSI IZIN (dipakai bersama oleh RLS di rls.sql dan view leaderboard)
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Helper: bolehkah pengguna saat ini melihat aktivitas ini?
--
-- Dibuat SECURITY DEFINER agar bisa membaca `activities` & `follows` tanpa
-- terjebak rekursi RLS. Hanya mengembalikan boolean, tidak membocorkan data.
-- ---------------------------------------------------------------------------
create or replace function public.can_view_activity(p_activity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.activities a
      join public.profiles owner on owner.id = a.user_id
     where a.id = p_activity_id
       and (
         -- Selalu boleh melihat milik sendiri.
         a.user_id = auth.uid()
         -- Aktivitas publik dari profil publik.
         or (
           a.visibility = 'everyone'
           and owner.is_private = false
         )
         -- Pengikut boleh melihat aktivitas 'followers' ATAU
         -- aktivitas apa pun dari akun privat yang mereka ikuti.
         or (
           exists (
             select 1 from public.follows f
              where f.follower_id = auth.uid()
                and f.following_id = a.user_id
           )
           and (
             a.visibility = 'followers'
             or owner.is_private = true
           )
         )
       )
  );
$$;

revoke all on function public.can_view_activity(uuid) from public;
grant execute on function public.can_view_activity(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Helper: bolehkah pengguna saat ini melihat profil ini?
-- Profil publik: semua orang. Profil privat: pemilik & pengikutnya.
-- ---------------------------------------------------------------------------
create or replace function public.can_view_profile(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
     where p.id = p_user_id
       and (
         p.id = auth.uid()
         or p.is_private = false
         or exists (
           select 1 from public.follows f
            where f.follower_id = auth.uid()
              and f.following_id = p.id
         )
       )
  );
$$;

revoke all on function public.can_view_profile(uuid) from public;
grant execute on function public.can_view_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- VIEWS
-- ---------------------------------------------------------------------------

-- Feed & detail aktivitas. Kolom di sini sengaja datar agar mudah dipetakan
-- ke model Dart (Activity.fromJson).
create or replace view public.activity_details as
select
  a.id,
  a.user_id,
  a.type::text              as type,
  a.title,
  a.description,
  a.started_at,
  a.distance_meters,
  a.moving_seconds,
  a.elapsed_seconds,
  a.elevation_gain,
  a.elevation_loss,
  a.avg_pace_sec_per_km,
  a.max_speed_kmh,
  a.avg_heart_rate,
  a.avg_cadence_spm,
  a.calories,
  a.kudos_count,
  a.comment_count,
  a.visibility::text        as visibility,
  a.map_polyline,
  a.achievements,
  a.created_at,
  true                      as synced
from public.activities a;

-- Leaderboard per periode. Dibuat sebagai view agar klien cukup
-- memilih kolom pengurutan (jarak / elevasi / pace).
--
-- Privasi: leaderboard hanya mengagregasi aktivitas yang BOLEH dilihat oleh
-- pengguna saat ini, memakai predikat yang sama dengan RLS
-- (public.can_view_activity). Artinya aktivitas 'followers' tidak dihitung
-- untuk non-pengikut, dan aktivitas profil privat tetap tersembunyi.
--
-- Karena memanggil fungsi SECURITY DEFINER, view ini harus berjalan sebagai
-- owner (security_invoker = false); lihat rls.sql.
create or replace view public.leaderboard_all_time as
select
  p.id            as user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  p.city,
  count(a.id)::int                          as activity_count,
  coalesce(sum(a.distance_meters), 0)       as total_distance_meters,
  coalesce(sum(a.elevation_gain), 0)        as total_elevation_meters,
  coalesce(
    min(a.avg_pace_sec_per_km) filter (
      where a.distance_meters >= 1000 and a.avg_pace_sec_per_km > 0
    ), 0)                                   as best_pace_sec_per_km
from public.profiles p
left join public.activities a
       on a.user_id = p.id
      and public.can_view_activity(a.id)
group by p.id, p.username, p.display_name, p.avatar_url, p.city
having count(a.id) > 0;

create or replace view public.leaderboard_weekly as
select
  p.id            as user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  p.city,
  count(a.id)::int                          as activity_count,
  coalesce(sum(a.distance_meters), 0)       as total_distance_meters,
  coalesce(sum(a.elevation_gain), 0)        as total_elevation_meters,
  coalesce(
    min(a.avg_pace_sec_per_km) filter (
      where a.distance_meters >= 1000 and a.avg_pace_sec_per_km > 0
    ), 0)                                   as best_pace_sec_per_km
from public.profiles p
join public.activities a
  on a.user_id = p.id
 and public.can_view_activity(a.id)
where a.started_at >= date_trunc('week', now())
group by p.id, p.username, p.display_name, p.avatar_url, p.city;

create or replace view public.leaderboard_monthly as
select
  p.id            as user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  p.city,
  count(a.id)::int                          as activity_count,
  coalesce(sum(a.distance_meters), 0)       as total_distance_meters,
  coalesce(sum(a.elevation_gain), 0)        as total_elevation_meters,
  coalesce(
    min(a.avg_pace_sec_per_km) filter (
      where a.distance_meters >= 1000 and a.avg_pace_sec_per_km > 0
    ), 0)                                   as best_pace_sec_per_km
from public.profiles p
join public.activities a
  on a.user_id = p.id
 and public.can_view_activity(a.id)
where a.started_at >= date_trunc('month', now())
group by p.id, p.username, p.display_name, p.avatar_url, p.city;

create or replace view public.leaderboard_yearly as
select
  p.id            as user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  p.city,
  count(a.id)::int                          as activity_count,
  coalesce(sum(a.distance_meters), 0)       as total_distance_meters,
  coalesce(sum(a.elevation_gain), 0)        as total_elevation_meters,
  coalesce(
    min(a.avg_pace_sec_per_km) filter (
      where a.distance_meters >= 1000 and a.avg_pace_sec_per_km > 0
    ), 0)                                   as best_pace_sec_per_km
from public.profiles p
join public.activities a
  on a.user_id = p.id
 and public.can_view_activity(a.id)
where a.started_at >= date_trunc('year', now())
group by p.id, p.username, p.display_name, p.avatar_url, p.city;

-- ---------------------------------------------------------------------------
-- OPSIONAL: PostGIS
--   Aktifkan bila ingin query spasial sungguhan (mis. "rute yang melewati
--   area ini"). Jalankan setelah `create extension postgis;`.
-- ---------------------------------------------------------------------------
-- alter table public.activity_points
--   add column if not exists geom geometry(Point, 4326);
-- update public.activity_points
--    set geom = st_setsrid(st_makepoint(lon, lat), 4326)
--  where geom is null;
-- create index if not exists activity_points_geom_idx
--   on public.activity_points using gist (geom);

-- ---------------------------------------------------------------------------
-- MAINTENANCE
-- ---------------------------------------------------------------------------
-- Perbarui cache statistik untuk semua profil (jalankan sekali setelah impor):
create or replace function public.rebuild_all_profile_stats()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Statistik aktivitas.
  update public.profiles p
     set activity_count         = agg.cnt,
         total_distance_meters  = agg.dist,
         total_elevation_meters = agg.elev
    from (
      select user_id,
             count(*)::int as cnt,
             coalesce(sum(distance_meters), 0) as dist,
             coalesce(sum(elevation_gain), 0)  as elev
        from public.activities
       group by user_id
    ) agg
   where p.id = agg.user_id;

  -- Profil tanpa aktivitas -> nol.
  update public.profiles p
     set activity_count = 0,
         total_distance_meters = 0,
         total_elevation_meters = 0
   where not exists (
     select 1 from public.activities a where a.user_id = p.id
   );

  -- Jumlah pengikut.
  update public.profiles p
     set follower_count = coalesce(f.cnt, 0)
    from (
      select following_id as uid, count(*)::int as cnt
        from public.follows group by following_id
    ) f
   where p.id = f.uid;

  update public.profiles p
     set follower_count = 0
   where not exists (
     select 1 from public.follows f where f.following_id = p.id
   );

  -- Jumlah mengikuti.
  update public.profiles p
     set following_count = coalesce(g.cnt, 0)
    from (
      select follower_id as uid, count(*)::int as cnt
        from public.follows group by follower_id
    ) g
   where p.id = g.uid;

  update public.profiles p
     set following_count = 0
   where not exists (
     select 1 from public.follows f where f.follower_id = p.id
   );
end $$;
