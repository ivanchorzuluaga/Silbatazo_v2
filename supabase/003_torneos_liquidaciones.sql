-- ============================================================
-- Migración: torneos con categorías/tarifas, canchas, partido por W,
-- árbitro-es-veedor, tarjetas con multa configurable y liquidaciones.
-- ============================================================
-- Cómo aplicar: pegar este archivo completo en el SQL Editor de Supabase
-- (proyecto ya en producción) y ejecutarlo una sola vez. Es aditivo: no
-- borra ni renombra nada de lo que ya existe, así que los partidos sueltos
-- de hoy (sin torneo con categorías) siguen funcionando exactamente igual.

-- ============================================================
-- CANCHAS
-- ============================================================
create table public.courts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- CATEGORÍAS POR TORNEO
-- ============================================================
create table public.tournament_categories (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null, -- "Sub-14", "Sub-15", etc.
  created_at timestamptz not null default now(),
  unique(tournament_id, name)
);

-- ============================================================
-- TARIFAS (una por categoría)
-- ============================================================
create table public.rates (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  category_id uuid not null unique references public.tournament_categories(id) on delete cascade,
  team_fee integer not null check(team_fee >= 0),      -- lo que paga cada equipo
  referee_fee integer not null check(referee_fee >= 0),-- para el árbitro
  observer_fee integer not null default 0 check(observer_fee >= 0), -- para el veedor
  silbatazo_fee integer not null check(silbatazo_fee >= 0),
  tournament_fee integer not null default 0 check(tournament_fee >= 0), -- para el organizador
  yellow_fee integer not null default 5000,
  yellow_silbatazo integer not null default 2500,
  yellow_tournament integer not null default 2500,
  red_fee integer not null default 10000,
  red_silbatazo integer not null default 6000,
  red_tournament integer not null default 4000,
  created_at timestamptz not null default now()
);

create index rates_tournament_idx on public.rates(tournament_id);

-- ============================================================
-- CONFIGURACIÓN ADICIONAL DE TORNEO
-- ============================================================
alter table public.tournaments
  add column requires_observer boolean not null default true,
  add column has_cards boolean not null default true,
  -- Cuando el árbitro mismo hace de veedor, cómo se reparte el valor_veedor
  -- entre Silbatazo y el torneo (deben sumar 100, se valida en la app).
  add column arbiter_observer_split_silbatazo_pct integer not null default 50,
  add column arbiter_observer_split_tournament_pct integer not null default 50;

-- ============================================================
-- PARTIDOS: cancha, categoría, tipo de servicio, por W, árbitro=veedor
-- ============================================================
alter table public.matches
  add column court_id uuid references public.courts(id),
  add column category_id uuid references public.tournament_categories(id),
  add column service_type text not null default 'completo'
    check (service_type in ('completo', 'solo_arbitraje')),
  add column arbiter_is_observer boolean not null default false,
  add column is_walkover boolean not null default false,
  add column w_team_id uuid references public.teams(id),
  -- Snapshot de la tarifa al crear el partido (igual que cards.fee): si
  -- luego se edita la tarifa de la categoría, los partidos ya jugados no
  -- cambian de valor.
  add column team_fee integer not null default 0,
  add column silbatazo_fee integer not null default 0,
  add column tournament_fee integer not null default 0;

create index matches_category_idx on public.matches(category_id);
create index matches_court_idx on public.matches(court_id);

-- ============================================================
-- TARJETAS: split Silbatazo/torneo (snapshot de la tarifa)
-- ============================================================
alter table public.cards
  add column silbatazo_fee integer not null default 0,
  add column tournament_fee integer not null default 0;

-- Backfill de tarjetas ya existentes, con el split por defecto documentado
-- en CLAUDE.md (amarilla 2.500/2.500, roja 6.000/4.000).
update public.cards set silbatazo_fee = 2500, tournament_fee = 2500 where card_type = 'yellow' and silbatazo_fee = 0 and tournament_fee = 0;
update public.cards set silbatazo_fee = 6000, tournament_fee = 4000 where card_type = 'red' and silbatazo_fee = 0 and tournament_fee = 0;

-- La multa y su split ahora salen de la tarifa de la categoría del
-- partido cuando existe; si el partido no tiene categoría (partido suelto,
-- igual que hoy) se mantienen los valores por defecto de siempre.
create or replace function public.set_card_fee() returns trigger language plpgsql as $$
declare
  r public.rates%rowtype;
  cat_id uuid;
begin
  select category_id into cat_id from public.matches where id = new.match_id;
  if cat_id is not null then
    select * into r from public.rates where category_id = cat_id;
  end if;
  if r.id is not null then
    if new.card_type = 'yellow' then
      new.fee := r.yellow_fee; new.silbatazo_fee := r.yellow_silbatazo; new.tournament_fee := r.yellow_tournament;
    else
      new.fee := r.red_fee; new.silbatazo_fee := r.red_silbatazo; new.tournament_fee := r.red_tournament;
    end if;
  else
    if new.card_type = 'yellow' then
      new.fee := 5000; new.silbatazo_fee := 2500; new.tournament_fee := 2500;
    else
      new.fee := 10000; new.silbatazo_fee := 6000; new.tournament_fee := 4000;
    end if;
  end if;
  return new;
end $$;

-- El trigger de restricción de columnas para veedor (002) debe dejar pasar
-- los dos campos nuevos sin bloquearlos también cuando el admin actualiza.
create or replace function public.cards_restrict_veedor_update() returns trigger language plpgsql as $$
begin
  if not public.is_admin() then
    new.match_id := old.match_id;
    new.team_side := old.team_side;
    new.player_name := old.player_name;
    new.card_type := old.card_type;
    new.fee := old.fee;
    new.silbatazo_fee := old.silbatazo_fee;
    new.tournament_fee := old.tournament_fee;
    new.recorded_by := old.recorded_by;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;

-- ============================================================
-- El veedor puede marcar su propio partido como "por W" (solo esas dos
-- columnas; el resto del partido sigue siendo admin-only). Mismo patrón
-- de trigger espejo que cards_restrict_veedor_update.
-- ============================================================
create or replace function public.matches_restrict_veedor_update() returns trigger language plpgsql as $$
begin
  if not public.is_admin() then
    new.tournament_id := old.tournament_id;
    new.client_id := old.client_id;
    new.local_team_id := old.local_team_id;
    new.visitor_team_id := old.visitor_team_id;
    new.name := old.name;
    new.match_date := old.match_date;
    new.match_time := old.match_time;
    new.place := old.place;
    new.match_type := old.match_type;
    new.status := old.status;
    new.service_value := old.service_value;
    new.officials_total := old.officials_total;
    new.client_to_silbatazo := old.client_to_silbatazo;
    new.client_to_officials := old.client_to_officials;
    new.silbatazo_to_officials := old.silbatazo_to_officials;
    new.notes := old.notes;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.court_id := old.court_id;
    new.category_id := old.category_id;
    new.service_type := old.service_type;
    new.arbiter_is_observer := old.arbiter_is_observer;
    new.team_fee := old.team_fee;
    new.silbatazo_fee := old.silbatazo_fee;
    new.tournament_fee := old.tournament_fee;
    -- is_walkover y w_team_id sí las puede tocar el veedor
  end if;
  return new;
end $$;
drop trigger if exists matches_restrict_veedor_update on public.matches;
create trigger matches_restrict_veedor_update before update on public.matches for each row execute function public.matches_restrict_veedor_update();

create policy "veedor marca por w en sus partidos" on public.matches for update using (
  id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
) with check (
  id in (select mo.match_id from public.match_observers mo join public.observers o on o.id = mo.observer_id where o.profile_id = auth.uid())
);

-- ============================================================
-- LIQUIDACIONES
-- ============================================================
create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  observer_id uuid not null references public.observers(id),
  start_date date not null,
  end_date date not null,
  total_collected integer not null default 0,       -- total recaudado (cobrado a equipos)
  total_paid_referees integer not null default 0,    -- lo que pagó a árbitros
  total_cards_collected integer not null default 0,  -- multas cobradas
  total_observer integer not null default 0,         -- lo que se queda el veedor
  total_silbatazo integer not null default 0,         -- lo que transfiere a Silbatazo
  total_tournament integer not null default 0,        -- lo que transfiere al torneo
  w_adjustment integer not null default 0,             -- deuda del torneo por partidos "por W"
  status text not null default 'pendiente' check (status in ('pendiente', 'cerrada')),
  notes text,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table public.settlement_matches (
  settlement_id uuid not null references public.settlements(id) on delete cascade,
  match_id uuid not null references public.matches(id),
  primary key (settlement_id, match_id)
);

create index settlements_observer_idx on public.settlements(observer_id);

alter table public.courts enable row level security;
alter table public.tournament_categories enable row level security;
alter table public.rates enable row level security;
alter table public.settlements enable row level security;
alter table public.settlement_matches enable row level security;

create policy "admins courts" on public.courts for all using(public.is_admin()) with check(public.is_admin());
create policy "admins tournament_categories" on public.tournament_categories for all using(public.is_admin()) with check(public.is_admin());
create policy "admins rates" on public.rates for all using(public.is_admin()) with check(public.is_admin());
create policy "admins settlements" on public.settlements for all using(public.is_admin()) with check(public.is_admin());
create policy "admins settlement_matches" on public.settlement_matches for all using(public.is_admin()) with check(public.is_admin());

-- ============================================================
-- my_assigned_matches: se amplía con cancha, categoría, tipo de servicio,
-- por W y el desglose financiero (cobrar por equipo / transferir a
-- Silbatazo / transferir al torneo) que pide la vista del veedor.
-- ============================================================
drop function if exists public.my_assigned_matches();
create function public.my_assigned_matches()
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
  report_submitted_at timestamptz,
  court_name text,
  category_name text,
  service_type text,
  is_walkover boolean,
  team_fee integer,
  silbatazo_fee integer,
  tournament_fee integer,
  local_team_id uuid,
  visitor_team_id uuid
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id, m.name, m.match_date, m.match_time, m.place, m.match_type,
    tl.name, tv.name, m.status, mo.agreed_value,
    mr.home_score, mr.away_score, mr.submitted_at,
    c.name, tc.name, m.service_type, m.is_walkover,
    m.team_fee, m.silbatazo_fee, m.tournament_fee,
    m.local_team_id, m.visitor_team_id
  from public.match_observers mo
  join public.observers o on o.id = mo.observer_id
  join public.matches m on m.id = mo.match_id
  left join public.teams tl on tl.id = m.local_team_id
  left join public.teams tv on tv.id = m.visitor_team_id
  left join public.match_reports mr on mr.match_id = m.id
  left join public.courts c on c.id = m.court_id
  left join public.tournament_categories tc on tc.id = m.category_id
  where o.profile_id = auth.uid()
  order by m.match_date, m.match_time;
$$;

grant execute on function public.my_assigned_matches() to authenticated;

-- ============================================================
-- pending_card_debts: tarjetas sin pagar de los dos equipos de un partido,
-- de partidos anteriores del mismo torneo (bloque "Novedades" del veedor).
-- Mismo filtro de pertenencia que ya usan las políticas de cards.
-- ============================================================
create or replace function public.pending_card_debts(p_match_id uuid)
returns table (
  card_id uuid,
  player_name text,
  card_type public.card_type,
  fee numeric,
  team_name text,
  match_name text,
  match_date date
)
language sql
security definer
set search_path = public
stable
as $$
  with m as (
    select * from public.matches where id = p_match_id
      and id in (
        select mo.match_id from public.match_observers mo
        join public.observers o on o.id = mo.observer_id
        where o.profile_id = auth.uid()
      )
  )
  select cd.id, cd.player_name, cd.card_type, cd.fee, t.name, mm.name, mm.match_date
  from m
  join public.matches mm on mm.tournament_id = m.tournament_id and mm.id <> m.id
    and mm.match_date <= m.match_date
    and (mm.local_team_id in (m.local_team_id, m.visitor_team_id) or mm.visitor_team_id in (m.local_team_id, m.visitor_team_id))
  join public.cards cd on cd.match_id = mm.id and cd.paid = false
  join public.teams t on t.id = (case when cd.team_side = 'local' then mm.local_team_id else mm.visitor_team_id end)
  where t.id in (m.local_team_id, m.visitor_team_id)
  order by mm.match_date desc;
$$;

grant execute on function public.pending_card_debts(uuid) to authenticated;
