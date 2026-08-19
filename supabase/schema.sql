-- Silbatazo Gestión — esquema inicial para Supabase/PostgreSQL
create extension if not exists pgcrypto;

create type public.match_status as enum ('pending','confirmed','finished','cancelled');
create type public.client_type as enum ('person','company','tournament');
create type public.official_role as enum ('central','assistant_1','assistant_2','other');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'admin' check (role = 'admin'),
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

