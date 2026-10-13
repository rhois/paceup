-- ============================================================================
--  PaceUp — Data contoh (SEEDER)
-- ============================================================================
--  Jalankan setelah schema.sql, rls.sql, dan functions.sql.
--
--  Cara pakai (SQL Editor Supabase / psql):
--
--      -- 1. Daftarkan satu akun lewat aplikasi (atau Dashboard -> Authentication).
--      -- 2. Jalankan skrip ini dengan email akun tersebut:
--
--      \set email 'kamu@contoh.com'
--      \i sql/seed.sql
--
--  Seeder ini akan:
--    * mengisi profil akun target,
--    * membuat 'teman' demo beserta follower relation (bila belum ada),
--    * menambahkan 6 aktivitas dengan titik GPS, elevasi, dan split,
--    * menambahkan kudos + komentar antar teman.
--
--  Aman dijalankan berulang (idempotent): aktivitas contoh memakai ID tetap
--  dan dihapus lebih dulu sebelum dibuat ulang.
-- ============================================================================

-- Tentukan email akun target di sini BILA memakai Supabase SQL Editor:
--   select set_config('paceup.seed_email', 'kamu@contoh.com', false);
-- Dari psql, cukup:  \set email 'kamu@contoh.com'  (lihat bawah)
\if :{?email}
  select set_config('paceup.seed_email', :'email', false);
\endif

do $$
declare
  v_email      text := nullif(current_setting('paceup.seed_email', true), '');
  v_user_id    uuid;
  v_friend_ids uuid[] := '{}';
  v_fid        uuid;
  v_names      text[] := array['Budi Santoso', 'Sari Wijaya', 'Andre Kusuma', 'Dita Putri'];
  v_usernames  text[] := array['budisantoso', 'sari_run', 'andrew', 'ditaputri'];
  v_cities     text[] := array['Bandung', 'Yogyakarta', 'Surabaya', 'Denpasar'];
  v_bios       text[] := array[
    'Trail runner. Suka naik gunung pagi-pagi.',
    'Marathoner. PR 3:58.',
    'Pace 4:30 target tahun ini.',
    'Lari santai tiap pagi.'
  ];
  i            int;
  a            int;
  v_activity   uuid;
  v_started    timestamptz;
  v_count      int;
  v_points     int;
  v_dist       double precision;
  v_pace       double precision;
  v_speed      double precision;
  g            int;
  v_week_start timestamptz := date_trunc('week', now());
begin
  -- ---------------------------------------------------------------- profil
  select id into v_user_id from public.profiles where username = split_part(v_email, '@', 1);
  if v_user_id is null then
    -- Fallback: cari lewat email di auth.users.
    select u.id into v_user_id
      from auth.users u
      join public.profiles p on p.id = u.id
     where u.email = v_email;
  end if;

  if v_email is null then
    raise exception 'Email target belum diset. Jalankan: select set_config(''paceup.seed_email'', ''emailmu@contoh.com'', false);';
  end if;

  if v_user_id is null then
    raise exception 'Pengguna dengan email % tidak ditemukan. Daftar dulu lewat aplikasi.', v_email;
  end if;

  update public.profiles
     set city = coalesce(nullif(city, ''), 'Jakarta'),
         bio  = coalesce(nullif(bio, ''), 'Mulai rutin lari tahun ini.'),
         weight_kg = 66
   where id = v_user_id;

  -- ------------------------------------------------------------- teman demo
  -- Teman demo dibuat hanya bila trigger auth sudah membuat profilnya.
  -- (Di Supabase, buat akun teman lewat Dashboard -> Authentication -> Users.)
  for i in 1..array_length(v_names, 1) loop
    select id into v_fid from public.profiles where username = v_usernames[i];
    if v_fid is not null then
      update public.profiles
         set display_name = v_names[i],
             city = v_cities[i],
             bio = v_bios[i]
       where id = v_fid;
      v_friend_ids := array_append(v_friend_ids, v_fid);

      insert into public.follows (follower_id, following_id)
      values (v_user_id, v_fid)
      on conflict do nothing;

      insert into public.follows (follower_id, following_id)
      values (v_fid, v_user_id)
      on conflict do nothing;
    end if;
  end loop;

  -- ------------------------------------------------------------- aktivitas
  -- Hapus aktivitas contoh lama (ID tetap) supaya seeder idempotent.
  delete from public.activities
   where id in (
     select ('cccccccc-0000-0000-0000-00000000000' || ds_idx)::uuid
       from generate_series(0, 5) as ds_idx
   )
   or id in (
     select ('dddddddd-0000-0000-0000-00000000000' || ds_idx)::uuid
       from generate_series(0, 5) as ds_idx
   );

  -- 6 aktivitas milik pengguna target.
  for a in 0..5 loop
    v_activity := ('cccccccc-0000-0000-0000-00000000000' || a)::uuid;

    -- Dua aktivitas pertama sengaja diletakkan di minggu berjalan supaya
    -- dasbor mingguan & leaderboard langsung berisi data. Sisanya lebih lama
    -- agar grafik 30 hari terlihat berisi.
    v_started := case
      when a = 0 then greatest(v_week_start, now() - interval '3 hours')
      when a = 1 then greatest(v_week_start, now() - interval '1 day')
      else now() - ((a * 2) || ' days')::interval
    end;
    v_dist     := (4 + a * 1.7) * 1000.0;          -- 4.0 .. 12.5 km
    v_pace     := 285 + a * 9;                      -- 4:45 .. 5:30 /km
    v_speed    := 1000.0 / v_pace;                  -- m/s
    v_points   := greatest(60, (v_dist / (v_speed * 4))::int);
    v_count    := 0;

    insert into public.activities (
      id, user_id, type, title, description, started_at,
      distance_meters, moving_seconds, elapsed_seconds,
      elevation_gain, elevation_loss, avg_pace_sec_per_km, max_speed_kmh,
      avg_heart_rate, avg_cadence_spm, calories,
      visibility, timezone, map_polyline,
      start_lat, start_lon, end_lat, end_lon
    )
    values (
      v_activity, v_user_id,
      case when a % 3 = 2 then 'trailRun' else 'run' end::activity_type,
      case a % 4
        when 0 then 'Morning run'
        when 1 then 'Easy run'
        when 2 then 'Tempo run'
        else 'Long run'
      end,
      case when a % 2 = 0 then 'Cuaca cerah, badan terasa enak.' else '' end,
      v_started,
      v_dist,
      (v_dist / v_speed)::int,
      ((v_dist / v_speed) * 1.04)::int,
      35 + a * 12,
      30 + a * 10,
      v_pace,
      v_speed * 3.6 * 1.35,
      148 + a,
      170 + (a % 5),
      round(v_dist / 1000.0 * 66 * 1.036)::int,
      case when a % 3 = 2 then 'everyone' else 'followers' end::visibility,
      'Asia/Jakarta',
      '',
      -6.2 - a * 0.01, 106.8 + a * 0.01,
      -6.2 - a * 0.01, 106.8 + a * 0.01
    );

    -- Titik GPS: lintasan melingkar dengan elevasi naik-turun.
    insert into public.activity_points (
      activity_id, seq, lat, lon, recorded_at,
      altitude, speed_mps, distance_delta, accuracy, cadence, heart_rate
    )
    select
      v_activity,
      gp,
      -6.2 - a * 0.01 + (v_dist / (2 * pi()) / 111320.0)
            * (1 + 0.15 * sin(gp * 0.05)) * cos(2 * pi() * gp / v_points),
      106.8 + a * 0.01 + (v_dist / (2 * pi()) / 111320.0)
            * (1 + 0.15 * sin(gp * 0.05)) * sin(2 * pi() * gp / v_points)
            / cos(radians(-6.2)),
      v_started + (gp * 4 || ' seconds')::interval,
      40 + 25 * sin(gp * 0.02) + (a * 3),
      v_speed * (0.95 + 0.1 * sin(gp * 0.07)),
      case when gp = 0 then 0 else v_speed * 4 end,
      5 + (gp % 6),
      168 + (gp % 12),
      146 + (gp % 20)
    from generate_series(0, v_points) gp;
  end loop;

  -- Tautkan start/end aktual dari titik GPS.
  update public.activities act
     set start_lat = f.lat, start_lon = f.lon
    from (
      select distinct on (activity_id) activity_id, lat, lon
        from public.activity_points
       order by activity_id, seq asc
    ) f
   where act.id = f.activity_id
     and act.id::text like 'cccccccc-%';

  update public.activities act
     set end_lat = l.lat, end_lon = l.lon
    from (
      select distinct on (activity_id) activity_id, lat, lon
        from public.activity_points
       order by activity_id, seq desc
    ) l
   where act.id = l.activity_id
     and act.id::text like 'cccccccc-%';

  -- --------------------------------------------- aktivitas milik teman demo
  if array_length(v_friend_ids, 1) > 0 then
    for a in 0..5 loop
      v_fid      := v_friend_ids[(a % array_length(v_friend_ids, 1)) + 1];
      v_activity := ('dddddddd-0000-0000-0000-00000000000' || a)::uuid;
      v_started  := case
        when a = 0 then greatest(v_week_start, now() - interval '6 hours')
        when a = 1 then greatest(v_week_start, now() - interval '2 days')
        else now() - ((a * 3) || ' days')::interval - interval '5 hours'
      end;
      v_dist     := (5 + a * 2.1) * 1000.0;
      v_pace     := 270 + a * 11;
      v_speed    := 1000.0 / v_pace;
      v_points   := greatest(60, (v_dist / (v_speed * 4))::int);

      insert into public.activities (
        id, user_id, type, title, started_at,
        distance_meters, moving_seconds, elapsed_seconds,
        elevation_gain, elevation_loss, avg_pace_sec_per_km, max_speed_kmh,
        avg_heart_rate, avg_cadence_spm, calories,
        visibility, timezone, start_lat, start_lon, end_lat, end_lon
      )
      values (
        v_activity, v_fid,
        case when a % 4 = 3 then 'trailRun' else 'run' end::activity_type,
        (array['Morning run','Easy run','Tempo run','Long run','Sunset run','Recovery run'])[a + 1],
        v_started,
        v_dist, (v_dist / v_speed)::int, ((v_dist / v_speed) * 1.05)::int,
        28 + a * 9, 24 + a * 8, v_pace, v_speed * 3.6 * 1.3,
        145 + a, 169 + (a % 6), round(v_dist / 1000.0 * 68 * 1.036)::int,
        case when a % 2 = 0 then 'everyone' else 'followers' end::visibility,
        'Asia/Jakarta',
        -6.9 + a * 0.02, 107.6 + a * 0.02,
        -6.9 + a * 0.02, 107.6 + a * 0.02
      );

      insert into public.activity_points (
        activity_id, seq, lat, lon, recorded_at,
        altitude, speed_mps, distance_delta, accuracy, cadence, heart_rate
      )
      select
        v_activity, gp,
        -6.9 + a * 0.02 + (v_dist / (2 * pi()) / 111320.0)
              * (1 + 0.12 * sin(gp * 0.06)) * cos(2 * pi() * gp / v_points),
        107.6 + a * 0.02 + (v_dist / (2 * pi()) / 111320.0)
              * (1 + 0.12 * sin(gp * 0.06)) * sin(2 * pi() * gp / v_points)
              / cos(radians(-6.9)),
        v_started + (gp * 4 || ' seconds')::interval,
        60 + 30 * sin(gp * 0.025),
        v_speed * (0.94 + 0.12 * sin(gp * 0.08)),
        case when gp = 0 then 0 else v_speed * 4 end,
        5 + (gp % 7), 170 + (gp % 10), 144 + (gp % 22)
      from generate_series(0, v_points) gp;
    end loop;
  end if;

  -- ------------------------------------------------------- kudos & komentar
  for v_activity in
    select id from public.activities
     where id::text like 'cccccccc-%' or id::text like 'dddddddd-%'
  loop
    -- Pemilik sendiri + sebagian teman memberi kudos.
    insert into public.kudos (activity_id, user_id)
    select v_activity, uid
      from (
        select v_user_id as uid
        union all
        select unnest(v_friend_ids)
      ) t
     where uid is not null
    on conflict do nothing;

    insert into public.comments (activity_id, user_id, body)
    select v_activity,
           v_user_id,
           (array['Semangat! 🔥', 'Pace-nya rapi banget.', 'Besok bareng, yuk.'])[1 + (random() * 2)::int]
     where not exists (
       select 1 from public.comments c where c.activity_id = v_activity
     );
  end loop;

  perform public.rebuild_all_profile_stats();

  raise notice 'Seeder selesai untuk % (%).', v_email, v_user_id;
end $$;

\echo 'Seed selesai. Buka aplikasi dan masuk untuk melihat feed.'
