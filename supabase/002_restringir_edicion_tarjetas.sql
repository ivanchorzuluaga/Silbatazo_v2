-- Migración: evita que un veedor pueda alterar el monto/jugador/tipo de una
-- tarjeta ya creada. Solo puede marcarla como pagada (paid/paid_at).
--
-- Por qué: la política RLS "veedor marca pago de tarjetas de sus partidos"
-- solo verifica que la tarjeta pertenezca a un partido asignado al veedor;
-- no restringe qué columnas puede cambiar. Sin este trigger, un veedor
-- podría llamar a update() con { fee: 0, player_name: '...', card_type: '...' }
-- sobre una tarjeta de su propio partido y la base de datos lo permitiría.
--
-- Cómo aplicar: pegar este archivo completo en el SQL Editor de Supabase
-- (proyecto ya en producción) y ejecutarlo una sola vez. Ya está incluido
-- también en schema.sql para instalaciones nuevas.

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

drop trigger if exists cards_restrict_veedor_update on public.cards;
create trigger cards_restrict_veedor_update before update on public.cards for each row execute function public.cards_restrict_veedor_update();
