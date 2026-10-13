-- ============================================================================
--  PaceUp — Fungsi RPC
-- ============================================================================
--  Jalankan setelah schema.sql dan rls.sql.
--
--  Fungsi di sini dipanggil klien lewat `supabase.rpc(...)`:
--    * personal_records(user_id)  -> daftar rekor pribadi (PR)
--    * best_effort(user_id, m)    -> waktu tercepat untuk jarak tertentu
--    * weekly_summary(user_id)    -> ringkasan mingguan
--    * nearby_activities(...)     -> aktivitas di sekitar lokasi
--    * search_athletes(query)     -> pencarian pelari
-- ============================================================================

-- ---------------------------------------------------------------------------
-- best_effort: waktu tercepat menempuh `p_target_meters` (rolling window).
--
-- Dipakai untuk PR 1K / 5K / 10K / Half. Perhitungan memakai jarak kumulatif
-- tiap titik GPS, lalu mencari pasangan titik terdekat yang mencapai target.
--
-- Catatan performa: kompleksitasnya O(n) per aktivitas berkat index
-- (activity_id, seq); aktivitas yang lebih pendek dari target langsung
-- disaring lebih dulu.
-- ---------------------------------------------------------------------------
create or replace function public.best_effort(
  p_user_id uuid,
  p_target_meters double precision
)
returns table (activity_id uuid, seconds double precision)
language sql
stable
security definer
set search_path = public
as $$
  with eligible as (
    select a.id
      from public.activities a
     where a.user_id = p_user_id
       and a.distance_meters >= p_target_meters
  ),
  pts as (
    select p.activity_id,
           p.recorded_at,
           sum(p.distance_delta) over (
             partition by p.activity_id order by p.seq
           ) as cum
      from public.activity_points p
      join eligible e on e.id = p.activity_id
  ),
  windows as (
    select a.activity_id,
           extract(epoch from (b.recorded_at - a.recorded_at))::double precision as secs
      from pts a
      join lateral (
        select recorded_at, cum
          from pts b
         where b.activity_id = a.activity_id
           and b.cum >= a.cum + p_target_meters
         order by b.cum
         limit 1
      ) b on true
  )
  select w.activity_id, min(w.secs) as seconds
    from windows w
   where w.secs > 0
   group by w.activity_id
   order by seconds asc
   limit 1;
$$;

grant execute on function public.best_effort(uuid, double precision) to authenticated;

-- ---------------------------------------------------------------------------
-- personal_records: daftar rekor pribadi untuk halaman profil.
-- ---------------------------------------------------------------------------
create or replace function public.personal_records(p_user_id uuid)
returns table (
  label text,
  value text,
  unit text,
  activity_id uuid,
  achieved_at timestamptz,
  sort_order int
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rec record;
  label_text text;
  secs double precision;
  act uuid;
begin
  -- 1. Jarak terjauh
  select a.id, a.distance_meters, a.started_at into rec
    from public.activities a
   where a.user_id = p_user_id
   order by a.distance_meters desc
   limit 1;

  if found then
    return query select
      'Jarak terjauh'::text,
      to_char(rec.distance_meters / 1000.0, 'FM990.00'),
      'km'::text,
      rec.id,
      rec.started_at,
      1;
  end if;

  -- 2. Best effort per jarak
  for rec in
    select * from (values
      (1000.0,   '1K tercepat',        2),
      (5000.0,   '5K tercepat',        3),
      (10000.0,  '10K tercepat',       4),
      (21097.5,  'Half marathon',      5)
    ) as t(target, lbl, ord)
  loop
    label_text := rec.lbl;
    select be.activity_id, be.seconds into act, secs
      from public.best_effort(p_user_id, rec.target) be;

    if secs is not null then
      return query select
        label_text,
        to_char((secs / 3600)::int, 'FM00') || ':' ||
          to_char(((secs::int % 3600) / 60), 'FM00') || ':' ||
          to_char((secs::int % 60), 'FM00'),
        ''::text,
        act,
        null::timestamptz,
        rec.ord::int;
    end if;
  end loop;

  -- 3. Pace terbaik (minimal 1 km)
  select a.id, a.avg_pace_sec_per_km, a.started_at into rec
    from public.activities a
   where a.user_id = p_user_id
     and a.distance_meters >= 1000
     and a.avg_pace_sec_per_km > 0
   order by a.avg_pace_sec_per_km asc
   limit 1;

  if found then
    return query select
      'Pace terbaik'::text,
      to_char((rec.avg_pace_sec_per_km / 60)::int, 'FM00') || ':' ||
        to_char((rec.avg_pace_sec_per_km::int % 60), 'FM00'),
      '/km'::text,
      rec.id,
      rec.started_at,
      6;
  end if;

  -- 4. Elevasi terbanyak
  select a.id, a.elevation_gain, a.started_at into rec
    from public.activities a
   where a.user_id = p_user_id
   order by a.elevation_gain desc
   limit 1;

  if found and rec.elevation_gain > 0 then
    return query select
      'Elevasi terbanyak'::text,
      rec.elevation_gain::int::text,
      'm'::text,
      rec.id,
      rec.started_at,
      7;
  end if;
end $$;

grant execute on function public.personal_records(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- weekly_summary: ringkasan minggu berjalan (Senin–Minggu).
-- ---------------------------------------------------------------------------
create or replace function public.weekly_summary(
  p_user_id uuid,
  p_reference timestamptz default now()
)
returns table (
  week_start date,
  distance_meters double precision,
  moving_seconds integer,
  elevation_gain double precision,
  activity_count integer,
  calories integer,
  daily_distances double precision[]
)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (
    select date_trunc('week', p_reference)::date as monday
  ),
  days as (
    select generate_series(0, 6) as offset
  ),
  per_day as (
    select (a.started_at at time zone 'Asia/Jakarta')::date as d,
           sum(a.distance_meters) as dist
      from public.activities a, bounds b
     where a.user_id = p_user_id
       and a.started_at >= b.monday
       and a.started_at < b.monday + interval '7 days'
     group by 1
  )
  select
    b.monday,
    coalesce(sum(a.distance_meters), 0),
    coalesce(sum(a.moving_seconds), 0)::int,
    coalesce(sum(a.elevation_gain), 0),
    count(a.id)::int,
    coalesce(sum(a.calories), 0)::int,
    (
      select array_agg(coalesce(pd.dist, 0) order by d.offset)
        from days d
        left join per_day pd on pd.d = b.monday + d.offset
    )
  from bounds b
  left join public.activities a
    on a.user_id = p_user_id
   and a.started_at >= b.monday
   and a.started_at < b.monday + interval '7 days'
  group by b.monday;
$$;

grant execute on function public.weekly_summary(uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- nearby_activities: aktivitas publik di sekitar titik tertentu.
-- Memakai bounding box sederhana (tanpa PostGIS).
-- ---------------------------------------------------------------------------
create or replace function public.nearby_activities(
  p_lat double precision,
  p_lon double precision,
  p_radius_km double precision default 10,
  p_limit integer default 30
)
returns table (
  id uuid,
  user_id uuid,
  username text,
  title text,
  started_at timestamptz,
  distance_meters double precision,
  distance_from_me_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select
      p_radius_km / 111.045 as dlat,
      p_radius_km / (111.045 * cos(radians(p_lat))) as dlon
  )
  select
    a.id,
    a.user_id,
    pr.username,
    a.title,
    a.started_at,
    a.distance_meters,
    -- Perkiraan jarak bidang datar; cukup akurat untuk radius < 50 km.
    111.045 * sqrt(
      power(a.start_lat - p_lat, 2) +
      power((a.start_lon - p_lon) * cos(radians(p_lat)), 2)
    ) as distance_from_me_km
  from public.activities a
  join public.profiles pr on pr.id = a.user_id
  cross join me
  where a.start_lat is not null
    and a.start_lon is not null
    and a.visibility = 'everyone'
    and pr.is_private = false
    and a.start_lat between p_lat - me.dlat and p_lat + me.dlat
    and a.start_lon between p_lon - me.dlon and p_lon + me.dlon
  order by distance_from_me_km asc, a.started_at desc
  limit p_limit;
$$;

grant execute on function public.nearby_activities(double precision, double precision, double precision, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- search_athletes: pencarian pelari berdasarkan nama/username.
-- ---------------------------------------------------------------------------
create or replace function public.search_athletes(
  p_query text,
  p_limit integer default 20
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  city text,
  follower_count integer,
  total_distance_meters double precision
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.city,
    p.follower_count,
    p.total_distance_meters
  from public.profiles p
  where p_query = ''
     or p.username ilike '%' || p_query || '%'
     or p.display_name ilike '%' || p_query || '%'
     or p.city ilike '%' || p_query || '%'
  order by
    -- Prioritaskan yang namanya persis berawalan query.
    (p.username ilike p_query || '%') desc,
    p.total_distance_meters desc
  limit p_limit;
$$;

grant execute on function public.search_athletes(text, integer) to authenticated;
