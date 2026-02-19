# Route25 Flutter App (MVP)

This folder contains the initial Flutter app for Route25.

Included in this MVP:
- Loads `assets/data/prd_routes_dataset.json`
- Uses current user location as origin (GPS)
- Destination input with stop suggestions
- Direct route matching (single-route)
- Route detail map with OSM tiles, polylines, and stop markers
- Route and stop list display
- Optional Supabase database loading with JSON fallback

## Important
Flutter SDK is not installed in this environment, so platform folders were not generated yet.

After installing Flutter, run:

```powershell
cd route25_app
flutter create .
flutter pub get
flutter run
```

`flutter create .` will generate `android/ios/web/windows/...` while keeping existing app code.

## Use your populated SQL database (Supabase)
If you imported `dataset/output/route25_dataset_dump.sql` to Supabase, run the app with:

```powershell
cd route25_app
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

If either define is missing, or if database fetch fails, the app automatically falls back to `assets/data/prd_routes_dataset.json`.

Current project default is already set to:
- `https://ldkhvyhxqnqptldbungk.supabase.co`
- `anon JWT key (hardcoded in lib/main.dart)`

## Location behavior
- Origin can be entered manually, or you can enable "Use current location as origin".
- The app requests location permission on first use.
- If current-location mode is enabled and location is unavailable, route search is disabled until location access is granted.

## Database access approach
The app now tries `rpc('get_route25_dataset')` first, then falls back to direct table reads from:
- `prd_meta`
- `prd_routes`
- `prd_route_stops`

If you see database fallback, ensure anon can read those tables (Supabase SQL Editor):

```sql
grant usage on schema public to anon, authenticated;
grant select on table public.prd_meta to anon, authenticated;
grant select on table public.prd_routes to anon, authenticated;
grant select on table public.prd_route_stops to anon, authenticated;

alter table public.prd_meta enable row level security;
alter table public.prd_routes enable row level security;
alter table public.prd_route_stops enable row level security;

drop policy if exists prd_meta_read_all on public.prd_meta;
create policy prd_meta_read_all on public.prd_meta for select using (true);

drop policy if exists prd_routes_read_all on public.prd_routes;
create policy prd_routes_read_all on public.prd_routes for select using (true);

drop policy if exists prd_route_stops_read_all on public.prd_route_stops;
create policy prd_route_stops_read_all on public.prd_route_stops for select using (true);

notify pgrst, 'reload schema';
```
