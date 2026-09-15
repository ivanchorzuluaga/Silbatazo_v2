# Silbatazo — Sistema Administrativo

## ¿Qué es este proyecto?
Sitio público (landing) + panel de administración + portal de veedores para Silbatazo, empresa colombiana de arbitraje de fútbol. Gestiona clientes, torneos (con categorías, tarifas y equipos fijos), partidos, árbitros, veedores, tarjetas amarillas/rojas, liquidaciones financieras semanales, e importación masiva de partidos por Excel.

## Stack tecnológico (real, en producción)
- **Frontend**: HTML + JS plano (`admin.html`, `veedor.html`, `index.html` — la landing, servida en la raíz). **Sin paso de build** — no hay `package.json`, no hay Next.js, no hay npm en este repo.
- **Base de datos**: Supabase (PostgreSQL) con Auth. Proyecto real: **`Silbatazo_v2`**, ref **`llilwqlqgbronvbsffav`**, región `us-east-1`. Los 4 admins tienen cuenta de Supabase Auth (rol `admin` en `profiles`). Los veedores **también** entran con correo/contraseña de Supabase Auth (rol `veedor`) — no hay acceso por link/token.
- **Cliente Supabase compartido**: `assets/js/supa.js` (`window.SilbatazoAuth`) — pide la config pública a `/api/config` (no hay `VITE_`/`NEXT_PUBLIC_` porque no hay build step) y expone `requireRole('admin'|'veedor', opts)`.
- **Backend serverless**: funciones en `/api/*.js` sobre Vercel (`create-veedor.js` usa `service_role` para crear el usuario del veedor; `gallery.js`/`testimonios.js`/`media.js` leen Google Drive de solo lectura para la landing — sección "Galería y testimonios" pendiente de configurar credenciales de Google, ver `PRODUCTION.md`).
- **Deploy**: Vercel, proyecto **`arbi-app-frontend`** (nombre heredado de una versión anterior en Vite, no renombrado), dominio de producción **`silbatazo.com`**, conectado al repo de GitHub (`ivanchorzuluaga/Silbatazo_v2`, rama `main`) — **cada `git push` a `main` despliega solo**. Sin build (Framework Preset = "Other", build/install/output command vacíos).
- **Esquema de base de datos**: `supabase/schema.sql` (base) + `supabase/002_restringir_edicion_tarjetas.sql` + `supabase/003_torneos_liquidaciones.sql` + `supabase/004_tarifas_avanzadas.sql` (migraciones incrementales, aditivas, en orden).

### Cómo aplicar un cambio de esquema
El CLI de Supabase ya está enlazado (`supabase link --project-ref llilwqlqgbronvbsffav`, requiere `supabase login` una vez por máquina/sesión). Un cambio de esquema es: crear `supabase/00N_descripcion.sql` nuevo (aditivo, nunca reescribir uno ya aplicado) y correr:
```
supabase db query --linked --file supabase/00N_descripcion.sql
```
Esto pega directo contra la base real vía la Management API (no pide contraseña de Postgres). Verificar con `supabase db query --linked "select ..."`. Para `CREATE OR REPLACE FUNCTION` que cambia las columnas de salida (`RETURNS TABLE`), Postgres exige `DROP FUNCTION` antes — no lo permite el `OR REPLACE` solo.

## Usuarios del sistema
| Rol | Descripción | Acceso |
|-----|-------------|--------|
| `admin` | Equipo Silbatazo | `admin.html` (`/admin`) — todo el sistema |
| `veedor` | Veedores, cuenta propia de Supabase Auth | `veedor.html` (`/veedor`) — solo sus partidos asignados + registro de eventos |

Los árbitros **no** usan el sistema — solo reciben información por WhatsApp.

## Tablas (nombres reales en `public.*`, en inglés — no traducir al escribir SQL)

- `profiles` — perfil de cada usuario de Supabase Auth, `role` = `admin`/`veedor`.
- `clients` — clientes que contratan partidos sueltos (persona/empresa/torneo).
- `referees` — árbitros.
- `tournaments` — torneos. Extendido con: `requires_observer`, `has_cards`, `arbiter_observer_split_silbatazo_pct`/`arbiter_observer_split_tournament_pct` (reparto cuando el árbitro es también el veedor).
- `tournament_categories` — categorías por torneo (ej. "Sub-14").
- `rates` — tarifa de una categoría: `team_fee` (lo que paga cada equipo), `referee_fee`, `assistant1_fee`/`assistant2_fee` (terna arbitral — **0 por defecto, y los campos de asistente en el formulario de partido se ocultan solos cuando están en 0**, la mayoría de categorías no los necesitan), `observer_fee`, `silbatazo_fee`, `tournament_fee`, y los valores de multa (`yellow_fee`/`yellow_silbatazo`/`yellow_tournament`, `red_fee`/`red_silbatazo`/`red_tournament`). `court_id` (nullable): `null` = tarifa por defecto de la categoría; con valor = **excepción de tarifa para esa cancha específica** dentro de la misma categoría (ej. un árbitro cobra más en una cancha lejana) — se agrega desde "Configurar torneo" → "Excepciones de tarifa por cancha". Índices únicos parciales (`rates_category_default_idx`, `rates_category_court_idx`) en vez de un simple `unique(category_id)`.
- `teams` — equipos fijos de un torneo (`equipos` en el lenguaje de negocio). Son fijos a propósito: el importador de partidos **no** crea equipos automáticamente si no coincide el nombre, marca error en la fila.
- `courts` — canchas (catálogo, evita duplicados). El formulario de partido y el importador **sí** crean una cancha nueva automáticamente si el nombre no existe todavía (las canchas no son una lista cerrada como los equipos).
- `matches` — partidos. Ver la sección de reglas de negocio abajo para la diferencia entre partido suelto y partido de torneo. Campos clave añadidos sobre el esquema original: `court_id`, `category_id`, `service_type` (`completo`/`solo_arbitraje`), `arbiter_is_observer`, `is_walkover`, `w_team_id`, y el snapshot de tarifa (`team_fee`, `silbatazo_fee`, `tournament_fee` — copiados de `rates` al crear/editar el partido, así una tarifa editada después no cambia partidos ya jugados). `officials_total` (columna original) se reutiliza como la suma árbitro central + asistente 1 + asistente 2.
- `match_officials` — uno o varios oficiales por partido (`role`: `central`/`assistant_1`/`assistant_2`/`other`), cada uno con su propio `agreed_value`.
- `observers` — veedores (`profile_id` los liga a su cuenta de Auth).
- `match_observers` — asignación de veedor a un partido + `agreed_value` (lo que se queda el veedor).
- `match_reports` — marcador final, lo llena el veedor.
- `cards` — tarjetas amarillas/rojas. `fee` + `silbatazo_fee`/`tournament_fee` los pone solo la base de datos (trigger `set_card_fee`) — nunca se mandan calculados desde el cliente. La multa depende solo de la categoría (no de la cancha, a diferencia de `referee_fee`) — el trigger siempre usa la tarifa por defecto (`court_id is null`) de la categoría del partido.
- `settlements` — liquidaciones semanales por veedor (solo las cierra el admin).
- `settlement_matches` — qué partidos cubre cada liquidación.

## Reglas de negocio

### Partido suelto / independiente (sin torneo, o torneo sin categoría elegida)
El sistema **no calcula nada** — es intencional. El precio de un partido independiente varía por cancha, distancia, cantidad de jugadores, etc., y eso lo decide el admin al momento, no una fórmula. El admin escribe manualmente cuánto cobra, cuánto paga al árbitro, y el ajuste de quién-le-paga-a-quién (`client_to_silbatazo`, `client_to_officials`, `silbatazo_to_officials`). No hay tarifa, no hay liquidación automática — este es el flujo original del sistema, sin cambios.

### Partido de torneo con categoría/tarifa
El precio de un partido de torneo **sí está pactado de antemano** y se respeta siempre — por eso se configura una vez por categoría (o por categoría+cancha si el torneo pactó algo distinto en una cancha puntual) en "Configurar torneo", y el formulario de partido lo autocompleta solo. Aun así, los campos autocompletados **quedan editables** para esa fila puntual (excepción de una sola vez, no de toda una cancha).
```
Cada equipo paga: team_fee (de la tarifa aplicable: la de la cancha si hay excepción, si no la de la categoría)
Total recaudado: team_fee × 2
Distribución (se paga completo, siempre):
  - Árbitro (+asistentes si la categoría los tiene): referee_fee + assistant1_fee + assistant2_fee
  - Veedor: observer_fee (se lo queda — vive en match_observers.agreed_value)
  - Silbatazo: silbatazo_fee
  - Torneo: el residual (recaudo − árbitro/asistentes − veedor − Silbatazo; normalmente = tournament_fee, ver fórmula unificada de liquidación abajo)
```

### Cuando el árbitro ES el veedor (`arbiter_is_observer`)
El `observer_fee` de la tarifa no se le paga a nadie — se reparte entre Silbatazo y el torneo según `tournaments.arbiter_observer_split_silbatazo_pct`/`arbiter_observer_split_tournament_pct`, y ese reparto queda ya sumado en el `silbatazo_fee`/`tournament_fee` grabados en el partido. No se crea fila en `match_observers`.

### Partido cancelado (`status = 'cancelled'`)
No se recaudó nada → nadie cobra nada (árbitro, veedor, Silbatazo, torneo: $0). No requiere lógica especial: un partido `cancelled` nunca es `finished`, y la liquidación solo suma partidos `finished` — automáticamente queda en $0 para todos.

### Partido por W (`is_walkover` + `w_team_id`)
Solo paga el equipo presente (`team_fee × 1`, no × 2). El árbitro (+asistentes), el veedor y Silbatazo **se pagan completos, igual que un partido normal** — es el torneo quien absorbe la diferencia. Fórmula unificada que usa `computeSettlement()` en `admin.html` (aplica igual a partido normal y a partido por W, sin rama especial):
```
recaudo = is_walkover ? team_fee : team_fee × 2
requerido = officials_total (árbitro+asistentes) + observer_fee (veedor) + silbatazo_fee
residual = recaudo − requerido
  residual ≥ 0 → el torneo se queda con ese residual (en un partido normal, coincide con tournament_fee)
  residual < 0 → el torneo debe cubrir el faltante (w_adjustment en la liquidación)
```

### Solo arbitraje (`service_type = 'solo_arbitraje'`)
No hay veedor asignado, no hay reparto complejo: todo lo que no es `referee_fee`(+asistentes) queda como `silbatazo_fee` (Silbatazo se queda con el resto), `tournament_fee = 0`.

### Tarjetas y multas
La multa y su reparto Silbatazo/torneo **los calcula la base de datos**, no el cliente (trigger `set_card_fee` en `cards`): si el partido tiene `category_id`, toma los valores de la tarifa **por defecto** de esa categoría (nunca la excepción por cancha); si no, usa los valores de siempre (amarilla $5.000 → 2.500/2.500, roja $10.000 → 6.000/4.000). Un veedor solo puede marcar `paid`/`paid_at` — un trigger (`cards_restrict_veedor_update`) le bloquea cualquier otro campo.

Deuda de tarjeta entre partidos del mismo equipo (mismo torneo): la función `pending_card_debts(match_id)` le muestra al veedor, al abrir un partido, las tarjetas sin pagar de esos mismos equipos en partidos anteriores del torneo ("Novedades").

### Editar partido
Botón "Editar" en cada partido (`admin.html` → Partidos) reabre el mismo formulario de "Nuevo partido", precargado, y guarda con `UPDATE` en vez de `INSERT` (reemplaza también `match_officials`/`match_observers`). Sirve para: corregir cualquier dato, reasignar árbitro/asistentes/veedor, y **marcar un partido como cancelado** después de creado (no hay botón separado para esto — es solo cambiar "Estado" a "Cancelado" y guardar).

### Importar partidos por Excel
`admin.html` → Partidos → "Importar Excel". Sube un `.xlsx` (parseo con SheetJS, cargado desde cdnjs) para un torneo ya configurado. Columnas: `fecha (AAAA-MM-DD), hora (HH:MM), cancha, categoria, equipo_local, equipo_visitante, tipo_servicio (opcional: completo/solo_arbitraje), arbitro_central (opcional), asistente_1 (opcional), asistente_2 (opcional), veedor (opcional), notas (opcional)`. Reglas de validación (vista previa fila por fila antes de importar):
- Categoría no encontrada, equipo local/visitante no encontrado → **error**, la fila no se importa (los equipos son fijos por torneo, no se crean solos).
- Cancha no encontrada → se **crea sola** (igual que en el formulario individual).
- Árbitro/asistente/veedor con nombre que no coincide con nadie registrado → **advertencia**, la fila sí se importa pero sin esa persona asignada (para no crear árbitros/veedores duplicados por un error de tipeo).
- El precio de cada fila se calcula igual que en el formulario individual (`computeMoneySnapshot`, compartida entre ambos flujos), resolviendo la tarifa por cancha si existe excepción.

### Liquidaciones
Las arma el admin desde `admin.html` → Liquidaciones: elige veedor + rango de fechas, el sistema junta los partidos `finished` de ese veedor en el rango (vía `match_observers`) + sus `cards` pagadas, calcula los totales con la fórmula unificada de arriba, y "Cerrar liquidación" graba en `settlements`/`settlement_matches` con `status='cerrada'`. Solo el admin cierra — el veedor no tiene esa vista.

## Valores monetarios
COP, enteros, sin decimales. Mostrar con formato `$40.000` (ya lo hace el helper `money()` en ambos HTML).

## Convenciones de código
- Todo vive en `admin.html`/`veedor.html`/`index.html` (landing) + `/api/*.js` + `assets/js/supa.js` — no hay carpetas `/app`, `/components`, `/lib` de Next.js.
- Nombres de tabla y columna en `snake_case`, **en inglés** (coinciden con el esquema real en `supabase/*.sql`), aunque el negocio y las conversaciones sean en español.
- **Cuidado con ids de campo que coinciden con propiedades nativas de `window`** (`name`, `status`, `top`, `location`, `history`, `length`, `closed`, `opener`, `parent`, `self`, `frames`...): un `<input id="name">` NO queda accesible como variable global bare `name` (window.name la tapa, y asignarle `.value` falla en silencio). Usar siempre `document.getElementById('name')`/`document.getElementById('status')` explícito para esos dos campos del formulario de partido; el resto de ids sí funcionan como referencia global bare (patrón ya usado en todo el archivo).
- Cambios de esquema: ver sección "Cómo aplicar un cambio de esquema" arriba.

## Verificación de cambios
No hay test suite ni entorno local con datos reales. El flujo usado en este proyecto: aplicar el SQL contra el proyecto real (`supabase db query --linked`), desplegar (`git push` → Vercel autodeploy), y probar en `silbatazo.com` con el navegador (skill `claude-in-chrome`) usando datos de prueba con un nombre reconocible (ej. "... Prueba (borrar)") que se borran al final por SQL. Ojo: `requestSubmit()` disparado desde JavaScript inyectado (para pruebas) puede duplicar el submit del formulario en este entorno — para clics reales de submit, usar el `computer` tool (click real), no `requestSubmit()`. Los triggers de la base (`matches_restrict_veedor_update`, `cards_restrict_veedor_update`) bloquean cambios a campos admin-only cuando la conexión no tiene un `auth.uid()` de admin real — esto incluye consultas SQL crudas vía `supabase db query` (no hay sesión de PostgREST) — para probar un cambio de estado hay que hacerlo a través del admin autenticado en el navegador, no por SQL directo.

## Notas importantes
- Los árbitros NO usan el sistema, solo reciben WhatsApp.
- Los veedores entran con su propia cuenta de Supabase Auth (correo/contraseña), creada desde `admin.html` → Veedores → + Agregar veedor (llama a `/api/create-veedor.js`).
- La seguridad real vive en las políticas RLS de Supabase (`is_admin()` + políticas por veedor), no en ocultar la `anon key` — esa key está pensada para ser pública.
- No hay acumulación de tarjetas entre partidos (cada partido es independiente); sí hay deuda de pago de multa entre partidos del mismo equipo en el mismo torneo (ver `pending_card_debts`).
- `Programaciones/` tiene los scripts de Python (`script_generar_programacion.py`, `script_generar_liquidacion_v4.py`) que el negocio usaba a mano para Copa Alegría antes de este sistema — sirvieron de referencia real para diseñar `rates`/asistentes/reglas de liquidación, pero ya no hace falta correrlos.
