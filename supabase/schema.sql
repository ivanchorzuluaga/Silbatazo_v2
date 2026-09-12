-- Silbatazo Gestión — esquema inicial para Supabase/PostgreSQL
create extension if not exists pgcrypto;

create type public.match_status as enum ('pending','confirmed','finished','cancelled');
create type public.client_type as enum ('person','company','tournament');
create type public.official_role as enum ('central','assistant_1','assistant_2','other');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'admin' check (role in ('admin','veedor')),
  created_at timestamptz not null default now()
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  type public.client_type not null default 'person',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.referees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  joined_on date,
  accepts_promotions boolean not null default false,
  availability text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete set null,
  name text not null,
  status text not null default 'active' check (status in ('draft','active','finished','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null,
  unique(tournament_id,name)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid references public.tournaments(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  local_team_id uuid references public.teams(id) on delete set null,
  visitor_team_id uuid references public.teams(id) on delete set null,
  name text not null,
  match_date date not null,
  match_time time not null,
  place text not null,
  match_type text not null,
  status public.match_status not null default 'pending',
  service_value numeric(12,2) not null default 0 check(service_value >= 0),
  officials_total numeric(12,2) not null default 0 check(officials_total >= 0),
  client_to_silbatazo numeric(12,2) not null default 0 check(client_to_silbatazo >= 0),
  client_to_officials numeric(12,2) not null default 0 check(client_to_officials >= 0),
  silbatazo_to_officials numeric(12,2) not null default 0 check(silbatazo_to_officials >= 0),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.match_officials (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  referee_id uuid not null references public.referees(id) on delete restrict,
  role public.official_role not null default 'central',
  agreed_value numeric(12,2) not null default 0 check(agreed_value >= 0),
  unique(match_id,referee_id,role)
);

create index matches_date_idx on public.matches(match_date,match_time);
create index matches_tournament_idx on public.matches(tournament_id);
create index matches_client_idx on public.matches(client_id);
create index officials_referee_idx on public.match_officials(referee_id);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.referees enable row level security;
alter table public.tournaments enable row level security;
alter table public.teams enable row level security;
alter table public.matches enable row level security;
alter table public.match_officials enable row level security;

create policy "admins profiles" on public.profiles for all using(public.is_admin()) with check(public.is_admin());
create policy "cualquiera lee su propio perfil" on public.profiles for select using (id = auth.uid());
create policy "admins clients" on public.clients for all using(public.is_admin()) with check(public.is_admin());
create policy "admins referees" on public.referees for all using(public.is_admin()) with check(public.is_admin());
create policy "admins tournaments" on public.tournaments for all using(public.is_admin()) with check(public.is_admin());
create policy "admins teams" on public.teams for all using(public.is_admin()) with check(public.is_admin());
create policy "admins matches" on public.matches for all using(public.is_admin()) with check(public.is_admin());
create policy "admins officials" on public.match_officials for all using(public.is_admin()) with check(public.is_admin());

create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create trigger clients_updated before update on public.clients for each row execute function public.set_updated_at();
create trigger referees_updated before update on public.referees for each row execute function public.set_updated_at();
create trigger tournaments_updated before update on public.tournaments for each row execute function public.set_updated_at();
create trigger matches_updated before update on public.matches for each row execute function public.set_updated_at();

-- ============================================================
-- Veedores: novedades de partido (marcador, tarjetas y multas)
-- ============================================================
-- Un veedor es un usuario con acceso muy restringido: solo ve los
-- partidos que tiene asignados (via match_observers), sin ningún
-- dato financiero del negocio (matches sigue siendo admin-only;
-- el veedor lee sus partidos a través de la función
-- my_assigned_matches(), que expone únicamente lo que necesita).

create type public.card_type as enum ('yellow','red');

create table public.observers ( -- "veedores"
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  name text not null,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.match_observers (
  match_id uuid primary key references public.matches(id) on delete cascade,
  observer_id uuid not null references public.observers(id) on delete restrict,
  agreed_value numeric(12,2) not null default 0 check(agreed_value >= 0),
  assigned_at timestamptz not null default now()
);

create table public.match_reports ( -- marcador final de cada partido
  match_id uuid primary key references public.matches(id) on delete cascade,
  home_score int check(home_score >= 0),
  away_score int check(away_score >= 0),
  notes text,
  submitted_by uuid references public.observers(id),
  submitted_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.cards ( -- tarjetas amarillas/rojas y su multa
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  team_side text not null check(team_side in ('local','visitante')),
  player_name text not null,
  card_type public.card_type not null,
  fee numeric(12,2) not null default 0 check(fee >= 0),
  paid boolean not null default false,
  paid_at timestamptz,
  recorded_by uuid references public.observers(id),
  created_at timestamptz not null default now()
);

create index match_observers_observer_idx on public.match_observers(observer_id);
create index cards_match_idx on public.cards(match_id);
create index cards_paid_idx on public.cards(paid);

-- La multa se fija sola según el tipo de tarjeta ($5.000 amarilla,
-- $10.000 roja), para que quede igual sin importar qué mande la app.
create or replace function public.set_card_fee() returns trigger language plpgsql as $$
begin
  if new.fee is null or new.fee = 0 then
    new.fee := case new.card_type when 'yellow' then 5000 when 'red' then 10000 else 0 end;
  end if;
  return new;
end $$;
create trigger cards_set_fee before insert on public.cards for each row execute function public.set_card_fee();

-- Un veedor solo puede marcar una tarjeta como pagada (paid/paid_at). La
-- política RLS de update para veedores solo filtra por partido asignado,
-- no por columna, así que sin esto un veedor podría, además de marcar el
-- pago, cambiarle el monto, el nombre del jugador o el tipo de tarjeta a
-- cualquier tarjeta de sus propios partidos. Este trigger deja esas
-- columnas intactas cuando quien actualiza no es admin.
create or replace function public.cards_restrict_veedor_update() returns trigger language plpgsql as $$
begin
  if not public.is_admin() then
    new.match_id := old.match_id;
    new.team_side := old.team_side;
    new.player_name := old.player_name;
    new.card_type := old.card_type;
    new.fee := old.fee;
    new.recorded_by := old.recorded_by;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
create trigger cards_restrict_veedor_update before update on public.cards for each row execute function public.cards_restrict_veedor_update();

create trigger observers_updated before update on public.observers for each row execute function public.set_updated_at();
create trigger match_reports_updated before update on public.match_reports for each row execute function public.set_updated_at();

alter table public.observers enable row level security;
alter table public.match_observers enable row level security;
alter table public.match_reports enable row level security;
alter table public.cards enable row level security;

-- Acceso admin total (igual que el resto de tablas)
create policy "admins observers" on public.observers for all using(public.is_admin()) with check(public.is_admin());
create policy "admins match_observers" on public.match_observers for all using(public.is_admin()) with check(public.is_admin());
create policy "admins match_reports" on public.match_reports for all using(public.is_admin()) with check(public.is_admin());
create policy "admins cards" on public.cards for all using(public.is_admin()) with check(public.is_admin());

-- Acceso del veedor: solo su propia fila y solo sus partidos asignados
create policy "veedor ve su perfil" on public.observers for select using (profile_id = auth.uid());

create policy "veedor ve sus asignaciones" on public.match_observers for select using (
  observer_id in (select id from public.observers where profile_id = auth.uid())
);

create policy "veedor lee marcador de sus partidos" on public.match_reports for select using (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);
create policy "veedor registra marcador de sus partidos" on public.match_reports for insert with check (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);
create policy "veedor edita marcador de sus partidos" on public.match_reports for update using (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
) with check (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);

create policy "veedor lee tarjetas de sus partidos" on public.cards for select using (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);
create policy "veedor registra tarjetas de sus partidos" on public.cards for insert with check (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);
create policy "veedor marca pago de tarjetas de sus partidos" on public.cards for update using (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
) with check (
  match_id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);

-- El veedor nunca consulta la tabla matches directamente (ahí vive la
-- plata del negocio). Esta función le entrega solo lo que necesita ver.
create or replace function public.my_assigned_matches()
returns table (
  match_id uuid,
  match_name text,
  match_date date,
  match_time time,
  place text,
  match_type text,
  team_local text,
  team_visitor text,
  status public.match_status,
  agreed_value numeric,
  home_score int,
  away_score int,
  report_submitted_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id, m.name, m.match_date, m.match_time, m.place, m.match_type,
    tl.name, tv.name, m.status, mo.agreed_value,
    mr.home_score, mr.away_score, mr.submitted_at
  from public.match_observers mo
  join public.observers o on o.id = mo.observer_id
  join public.matches m on m.id = mo.match_id
  left join public.teams tl on tl.id = m.local_team_id
  left join public.teams tv on tv.id = m.visitor_team_id
  left join public.match_reports mr on mr.match_id = m.id
  where o.profile_id = auth.uid()
  order by m.match_date, m.match_time;
$$;

grant execute on function public.my_assigned_matches() to authenticated;

