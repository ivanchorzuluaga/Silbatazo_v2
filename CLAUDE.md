# Silbatazo — Sistema Administrativo

## ¿Qué es este proyecto?
Sitio público (landing) + panel de administración + portal de veedores para Silbatazo, empresa colombiana de arbitraje de fútbol. Gestiona clientes, torneos (con categorías y tarifas), partidos, árbitros, veedores, tarjetas amarillas/rojas y liquidaciones financieras semanales.

## Stack tecnológico (real, en producción)
- **Frontend**: HTML + JS plano (`admin.html`, `veedor.html`, `index.html` — la landing, servida en la raíz `silbatazo.com/`). **Sin paso de build** — no hay `package.json`, no hay Next.js, no hay npm en este repo.
- **Base de datos**: Supabase (PostgreSQL) con Auth. Los 4 admins tienen cuenta de Supabase Auth (rol `admin` en `profiles`). Los veedores **también** entran con correo/contraseña de Supabase Auth (rol `veedor`) — no hay acceso por link/token.
- **Cliente Supabase compartido**: `assets/js/supa.js` (`window.SilbatazoAuth`) — pide la config pública a `/api/config` (no hay `VITE_`/`NEXT_PUBLIC_` porque no hay build step) y expone `requireRole('admin'|'veedor', opts)`.
- **Backend serverless**: funciones en `/api/*.js` sobre Vercel (`create-veedor.js` usa `service_role` para crear el usuario del veedor; `gallery.js`/`testimonios.js`/`media.js` leen Google Drive de solo lectura para la landing).
- **Deploy**: Vercel, sin build (sitio estático + funciones `/api`).
- **Esquema de base de datos**: `supabase/schema.sql` (base) + `supabase/002_restringir_edicion_tarjetas.sql` + `supabase/003_torneos_liquidaciones.sql` (migraciones incrementales, se pegan a mano en el SQL Editor de Supabase — no hay Supabase CLI enlazado a este repo).

## Usuarios del sistema
| Rol | Descripción | Acceso |
|-----|-------------|--------|
| `admin` | Equipo Silbatazo (4 personas) | `admin.html` — todo el sistema |
| `veedor` | Veedores (6-7), cuenta propia de Supabase Auth | `veedor.html` — solo sus partidos asignados + registro de eventos |

Los árbitros **no** usan el sistema — solo reciben información por WhatsApp.

## Tablas (nombres reales en `public.*`, en inglés — no traducir al escribir SQL)

- `profiles` — perfil de cada usuario de Supabase Auth, `role` = `admin`/`veedor`.
- `clients` — clientes que contratan partidos sueltos (persona/empresa/torneo).
- `referees` — árbitros.
- `tournaments` — torneos. Extendido con: `requires_observer`, `has_cards`, `arbiter_observer_split_silbatazo_pct`/`arbiter_observer_split_tournament_pct` (reparto cuando el árbitro es también el veedor).
- `tournament_categories` — categorías por torneo (ej. "Sub-14"), 1:1 con su `rates`.
- `rates` — tarifa de una categoría: `team_fee` (lo que paga cada equipo), `referee_fee`, `observer_fee`, `silbatazo_fee`, `tournament_fee`, y los valores de multa (`yellow_fee`/`yellow_silbatazo`/`yellow_tournament`, `red_fee`/`red_silbatazo`/`red_tournament`).
- `teams` — equipos fijos de un torneo (`equipos` en el lenguaje de negocio).
- `courts` — canchas (catálogo, evita duplicados al armar partidos).
- `matches` — partidos. Puede ser **suelto** (sin `tournament_id`/`category_id`, usa los campos manuales `service_value`/`officials_total`/`client_to_*` de siempre) o **de torneo con tarifa** (`category_id` set → `team_fee`/`silbatazo_fee`/`tournament_fee` quedan grabados como *snapshot* de la tarifa al crear el partido, igual que ya hace `cards.fee`). Además: `court_id`, `service_type` (`completo`/`solo_arbitraje`), `arbiter_is_observer`, `is_walkover`, `w_team_id`.
- `match_officials` — árbitro(s) asignados a un partido (rol `central`, etc).
- `observers` — veedores (`profile_id` los liga a su cuenta de Auth).
- `match_observers` — asignación de veedor a un partido + `agreed_value`.
- `match_reports` — marcador final, lo llena el veedor.
- `cards` — tarjetas amarillas/rojas. `fee` + `silbatazo_fee`/`tournament_fee` los pone solo la base de datos (trigger `set_card_fee`, ver abajo) — nunca se mandan calculados desde el cliente.
- `settlements` — liquidaciones semanales por veedor (solo las cierra el admin).
- `settlement_matches` — qué partidos cubre cada liquidación.

## Reglas de negocio

### Partido suelto (sin torneo con categoría)
Sigue funcionando exactamente como el sistema original: el admin escribe manualmente cuánto cobra, cuánto paga al árbitro, y el ajuste de quién-le-paga-a-quién (`client_to_silbatazo`, `client_to_officials`, `silbatazo_to_officials`). No hay tarifa, no hay liquidación automática.

### Partido de torneo con categoría/tarifa
```
Cada equipo paga: team_fee (de la tarifa de su categoría)
Total recaudado: team_fee × 2
Distribución:
  - Árbitro: referee_fee (se le paga en el partido)
  - Veedor: observer_fee (se lo queda — vive en match_observers.agreed_value)
  - Silbatazo: silbatazo_fee (veedor transfiere)
  - Torneo: tournament_fee (veedor transfiere, si el torneo tiene organizador externo)
```

### Cuando el árbitro ES el veedor (`arbiter_is_observer`)
El `observer_fee` de la tarifa no se le paga a nadie — se reparte entre Silbatazo y el torneo según `tournaments.arbiter_observer_split_silbatazo_pct`/`arbiter_observer_split_tournament_pct`, y ese reparto queda ya sumado en el `silbatazo_fee`/`tournament_fee` grabados en el partido. No se crea fila en `match_observers`.

### Partido por W (`is_walkover` + `w_team_id`)
Solo paga el equipo presente (`team_fee × 1`, no × 2). El faltante lo debe cubrir el torneo — en la liquidación esto se ve como `w_adjustment` (la app suma `silbatazo_fee + tournament_fee` del partido a ese ajuste, en vez de contarlo como transferencia real de esa semana; ver nota de suposición en `supabase/003_torneos_liquidaciones.sql`).

### Solo arbitraje (`service_type = 'solo_arbitraje'`)
No hay veedor asignado, no hay reparto complejo: todo lo que no es `referee_fee` queda como `silbatazo_fee` (Silbatazo se queda con el resto), `tournament_fee = 0`.

### Tarjetas y multas
La multa y su reparto Silbatazo/torneo **los calcula la base de datos**, no el cliente (trigger `set_card_fee` en `cards`): si el partido tiene `category_id`, toma los valores de `rates`; si no, usa los valores por defecto de siempre (amarilla $5.000 → 2.500/2.500, roja $10.000 → 6.000/4.000). Un veedor solo puede marcar `paid`/`paid_at` — un trigger (`cards_restrict_veedor_update`) le bloquea cualquier otro campo.

Deuda de tarjeta entre partidos del mismo equipo (mismo torneo): la función `pending_card_debts(match_id)` le muestra al veedor, al abrir un partido, las tarjetas sin pagar de esos mismos equipos en partidos anteriores del torneo ("Novedades").

### Liquidaciones
Las arma el admin desde `admin.html` → Liquidaciones: elige veedor + rango de fechas, el sistema junta los partidos `finished` de ese veedor en el rango (vía `match_observers`) + sus `cards` pagadas, calcula los totales según las reglas de arriba, y "Cerrar liquidación" graba en `settlements`/`settlement_matches` con `status='cerrada'`. Solo el admin cierra — el veedor no tiene esa vista.

## Valores monetarios
COP, enteros, sin decimales. Mostrar con formato `$40.000` (ya lo hace el helper `money()` en ambos HTML).

## Convenciones de código
- Todo vive en `admin.html`/`veedor.html`/`index.html` (landing) + `/api/*.js` + `assets/js/supa.js` — no hay carpetas `/app`, `/components`, `/lib` de Next.js.
- Nombres de tabla y columna en `snake_case`, **en inglés** (coinciden con el esquema real en `supabase/*.sql`), aunque el negocio y las conversaciones sean en español.
- Cambios de esquema: agregar un archivo `supabase/00N_descripcion.sql` nuevo (migración incremental, aditiva). Una instalación nueva corre `schema.sql` y luego cada `00N_*.sql` en orden. El CLI de Supabase (`supabase`) ya está enlazado al proyecto real (`supabase link --project-ref llilwqlqgbronvbsffav`) — los cambios de esquema se aplican con `supabase db query --linked --file supabase/00N_....sql`, no hace falta pegar nada a mano en el SQL Editor.

## Notas importantes
- Los árbitros NO usan el sistema, solo reciben WhatsApp.
- Los veedores entran con su propia cuenta de Supabase Auth (correo/contraseña), creada desde `admin.html` → Veedores → + Agregar veedor (llama a `/api/create-veedor.js`).
- La seguridad real vive en las políticas RLS de Supabase (`is_admin()` + políticas por veedor), no en ocultar la `anon key` — esa key está pensada para ser pública.
- No hay acumulación de tarjetas entre partidos (cada partido es independiente); sí hay deuda de pago de multa entre partidos del mismo equipo en el mismo torneo (ver `pending_card_debts`).
