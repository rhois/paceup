-- ============================================================================
--  PaceUp — Row Level Security (RLS)
-- ============================================================================
--  Jalankan setelah schema.sql.
--
--  Prinsip:
--    * Semua tabel tertutup secara default (deny by default).
--    * Aktivitas hanya bisa dilihat pemilik, publik, atau pengikut —
--      menghormati visibilitas per-aktivitas DAN profil privat.
--    * Titik GPS (rute) mengikuti izin aktivitas induknya.
--
--  Catatan penting soal view:
--    * `activity_details` memakai `security_invoker = true` supaya RLS tabel
--      `activities` tetap berlaku. Tanpa itu, view berjalan sebagai owner dan
--      membocorkan aktivitas "only_me".
--    * View leaderboard dibiarkan berjalan sebagai owner karena perlu agregat
--      lintas pengguna, tetapi hanya menghitung aktivitas yang lolos
--      `public.can_view_activity()` — jadi privasi tetap terjaga.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Catatan: fungsi helper `can_view_activity()` & `can_view_profile()`
-- didefinisikan di schema.sql karena dipakai juga oleh view leaderboard.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Aktifkan RLS
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.activities      enable row level security;
alter table public.activity_points enable row level security;
alter table public.kudos           enable row level security;
alter table public.comments        enable row level security;
alter table public.follows         enable row level security;

-- ===========================================================================
-- profiles
-- ===========================================================================
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select"
  on public.profiles for select
  to authenticated
  using (true);  -- nama/username/avatar bersifat publik; aktivitasnya yang dijaga

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ===========================================================================
-- activities
-- ===========================================================================
drop policy if exists "activities_select" on public.activities;
create policy "activities_select"
  on public.activities for select
  to authenticated
  using (public.can_view_activity(id));

drop policy if exists "activities_insert_own" on public.activities;
create policy "activities_insert_own"
  on public.activities for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "activities_update_own" on public.activities;
create policy "activities_update_own"
  on public.activities for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "activities_delete_own" on public.activities;
create policy "activities_delete_own"
  on public.activities for delete
  to authenticated
  using (user_id = auth.uid());

-- ===========================================================================
-- activity_points  (rute mengikuti izin aktivitas induk)
-- ===========================================================================
drop policy if exists "activity_points_select" on public.activity_points;
create policy "activity_points_select"
  on public.activity_points for select
  to authenticated
  using (public.can_view_activity(activity_id));

drop policy if exists "activity_points_insert_own" on public.activity_points;
create policy "activity_points_insert_own"
  on public.activity_points for insert
  to authenticated
  with check (
    exists (
      select 1 from public.activities a
       where a.id = activity_id
         and a.user_id = auth.uid()
    )
  );

drop policy if exists "activity_points_delete_own" on public.activity_points;
create policy "activity_points_delete_own"
  on public.activity_points for delete
  to authenticated
  using (
    exists (
      select 1 from public.activities a
       where a.id = activity_id
         and a.user_id = auth.uid()
    )
  );

-- ===========================================================================
-- kudos
-- ===========================================================================
drop policy if exists "kudos_select" on public.kudos;
create policy "kudos_select"
  on public.kudos for select
  to authenticated
  using (public.can_view_activity(activity_id));

drop policy if exists "kudos_insert_own" on public.kudos;
create policy "kudos_insert_own"
  on public.kudos for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.can_view_activity(activity_id)
  );

drop policy if exists "kudos_delete_own" on public.kudos;
create policy "kudos_delete_own"
  on public.kudos for delete
  to authenticated
  using (user_id = auth.uid());

-- ===========================================================================
-- comments
-- ===========================================================================
drop policy if exists "comments_select" on public.comments;
create policy "comments_select"
  on public.comments for select
  to authenticated
  using (public.can_view_activity(activity_id));

drop policy if exists "comments_insert_own" on public.comments;
create policy "comments_insert_own"
  on public.comments for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.can_view_activity(activity_id)
  );

drop policy if exists "comments_update_own" on public.comments;
create policy "comments_update_own"
  on public.comments for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_delete_own"
  on public.comments for delete
  to authenticated
  using (user_id = auth.uid());

-- ===========================================================================
-- follows
-- ===========================================================================
drop policy if exists "follows_select" on public.follows;
create policy "follows_select"
  on public.follows for select
  to authenticated
  using (true);  -- daftar pengikut bersifat publik

drop policy if exists "follows_insert_own" on public.follows;
create policy "follows_insert_own"
  on public.follows for insert
  to authenticated
  with check (follower_id = auth.uid());

drop policy if exists "follows_delete_own" on public.follows;
create policy "follows_delete_own"
  on public.follows for delete
  to authenticated
  using (follower_id = auth.uid());

-- ===========================================================================
-- GRANTS (Supabase biasanya sudah mengatur default privileges; ini eksplisit
-- supaya skrip bisa dipakai di Postgres biasa juga).
-- ===========================================================================
grant usage on schema public to anon, authenticated;

grant select on public.profiles to authenticated;
grant insert, update on public.profiles to authenticated;

grant select, insert, update, delete on public.activities to authenticated;
grant select, insert, delete on public.activity_points to authenticated;
grant select, insert, delete on public.kudos to authenticated;
grant select, insert, update, delete on public.comments to authenticated;
grant select, insert, delete on public.follows to authenticated;

grant usage, select on all sequences in schema public to authenticated;

grant select on public.activity_details to authenticated;
grant select on public.leaderboard_weekly to authenticated;
grant select on public.leaderboard_monthly to authenticated;
grant select on public.leaderboard_yearly to authenticated;
grant select on public.leaderboard_all_time to authenticated;

-- ============================================================================
-- VIEW & RLS
-- ============================================================================
-- `activity_details` HARUS memakai security_invoker, jika tidak view berjalan
-- sebagai owner dan menembus RLS tabel `activities` (aktivitas 'only_me' akan
-- bocor ke semua orang).
alter view public.activity_details set (security_invoker = true);

-- View leaderboard justru sebaliknya: perlu membaca agregat lintas pengguna,
-- jadi dibiarkan sebagai security definer. Kebocoran dicegah di dalam definisi
-- view dengan menyaring `visibility <> 'only_me'` (lihat schema.sql).
alter view public.leaderboard_weekly     set (security_invoker = false);
alter view public.leaderboard_monthly    set (security_invoker = false);
alter view public.leaderboard_yearly     set (security_invoker = false);
alter view public.leaderboard_all_time   set (security_invoker = false);
