-- ============================================================
-- Migración: terna arbitral (asistentes) y tarifas con excepción
-- por cancha, dentro de la misma categoría de torneo.
-- ============================================================
-- Cómo aplicar: pegar este archivo completo en el SQL Editor de Supabase
-- y ejecutarlo una sola vez. Aditiva — no borra ni renombra nada.

alter table public.rates
  add column if not exists assistant1_fee integer not null default 0,
  add column if not exists assistant2_fee integer not null default 0,
  add column if not exists court_id uuid references public.courts(id);

-- Antes había una sola tarifa por categoría (unique(category_id), agregada
-- en 003 vía "category_id uuid not null unique"). Ahora puede haber una
-- tarifa por defecto (court_id null) y, opcionalmente, una excepción por
-- cancha (court_id set) para la misma categoría.
alter table public.rates drop constraint if exists rates_category_id_key;

create unique index if not exists rates_category_default_idx
  on public.rates(category_id) where court_id is null;
create unique index if not exists rates_category_court_idx
  on public.rates(category_id, court_id) where court_id is not null;

-- La multa de tarjeta sigue dependiendo solo de la categoría (no de la
-- cancha) — con varias tarifas por categoría posibles ahora, hay que fijar
-- explícitamente cuál usar (la tarifa por defecto, court_id is null), o
-- "select into" tomaría una fila cualquiera.
create or replace function public.set_card_fee() returns trigger language plpgsql as $$
declare
  r public.rates%rowtype;
  cat_id uuid;
begin
  select category_id into cat_id from public.matches where id = new.match_id;
  if cat_id is not null then
    select * into r from public.rates where category_id = cat_id and court_id is null;
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
