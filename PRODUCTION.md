# Puesta en producción de Silbatazo Gestión

**Estado: ya está en producción.** Este documento queda como referencia de cómo se montó y qué falta; para el contexto vigente del sistema (esquema, reglas de negocio, convenciones) ver `CLAUDE.md`.

## Arquitectura real (ya montada)

- **Frontend y dominio:** proyecto de Vercel **`arbi-app-frontend`** (nombre heredado de una versión anterior en Vite — no se renombró), dominio de producción **`silbatazo.com`**. Framework Preset en "Other" (sitio estático, sin build), conectado por Git al repo de GitHub — cada `git push` a `main` despliega solo.
- **Base de datos y autenticación:** Supabase, proyecto **`Silbatazo_v2`** (ref `llilwqlqgbronvbsffav`, región `us-east-1`).
- **Código:** repositorio privado `ivanchorzuluaga/Silbatazo_v2`.
- **Usuarios:** los administradores del equipo Silbatazo, creados manualmente en Supabase Auth + una fila en `profiles` con `role='admin'`.

## 1. Supabase (ya hecho)

El esquema completo (`schema.sql` + `002` + `003` + `004`, en ese orden) ya está aplicado contra el proyecto real. Para aplicar una migración nueva:
```
supabase login              # una vez por máquina/sesión (abre el navegador)
supabase link --project-ref llilwqlqgbronvbsffav
supabase db query --linked --file supabase/00N_descripcion.sql
```
No hace falta pegar nada a mano en el SQL Editor ni conocer la contraseña de Postgres — el CLI habla con la Management API usando el token de `supabase login`.

Para agregar un admin nuevo: crearlo en **Authentication → Users** (Supabase dashboard) con "Auto Confirm User", y luego:
```sql
insert into public.profiles (id, full_name, role)
select id, 'Nombre del administrador', 'admin' from auth.users where email = 'correo@ejemplo.com';
```
(se puede correr con `supabase db query --linked "..."`, sin tocar el dashboard).

## 2. Vercel (ya hecho)

Las tres variables ya están puestas en el proyecto `arbi-app-frontend` (Settings → Environment Variables), solo en **Production**:
- `SUPABASE_URL` = `https://llilwqlqgbronvbsffav.supabase.co`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (**nunca** se usa en el navegador; solo la leen las funciones serverless de `/api`, como `create-veedor.js`)

Si se quiere probar con `vercel deploy` (preview, sin `--prod`) antes de promover a producción, hay que agregar las mismas tres también a **Preview**/**Development** — hoy no están ahí.

Nota: este sitio no tiene paso de build, así que estas variables no se inyectan en el HTML directamente. `admin.html` y `veedor.html` piden la URL y la anon key al cargar a través de `/api/config` (una función serverless que simplemente las lee del entorno).

## 3. Checklist recurrente (repetir tras cambios grandes de esquema o de dinero)

- Confirmar que un usuario sin sesión no puede leer ni modificar tablas (RLS).
- Probar creación, edición y **eliminación** de clientes, árbitros, torneos, canchas y partidos.
- Probar un partido con árbitro central + 2 asistentes (categoría con terna arbitral).
- Verificar la fórmula de liquidación con un caso de cada tipo: partido normal, por W, cancelado (ver ejemplos numéricos verificados en `CLAUDE.md` → "Partido por W").
- Configurar alertas de uso en Supabase y revisar crecimiento de la base mensualmente.
- Exportar una copia (`supabase db dump` o desde el dashboard) antes de cambios grandes mientras se use el plan gratuito.

## 4. Paso recomendado de planes

1. Desarrollo y pruebas: Supabase Free (plan actual).
2. Operación diaria: Supabase Pro para evitar pausas y contar con respaldos automáticos.
3. Mantener Vercel actual mientras el consumo siga dentro de su plan.

## 5. Galería y testimonios automáticos desde Google Drive

La landing tiene dos secciones (`#galeria` y `#testimonios`) que se llenan solas leyendo carpetas de Google Drive, usando tres funciones serverless en `/api` (`gallery.js`, `testimonios.js`, `media.js`). Para activarlas hace falta una cuenta de servicio de Google con acceso de **solo lectura** a exactamente dos carpetas: `Fotos` y `Testimonios`. Nunca se le da acceso a `Documentos` (ahí vive `Accesos`, `Gastos` y documentos legales).

Pasos (los hace quien tenga acceso a Google Cloud y a Vercel — Claude no puede hacerlos porque requieren la consola de Google Cloud y el dashboard de Vercel):

1. En [Google Cloud Console](https://console.cloud.google.com), crear un proyecto (o usar uno existente) y habilitar la **Google Drive API**.
2. Crear una **cuenta de servicio** (IAM & Admin → Service Accounts). No necesita ningún rol de proyecto.
3. Generar una **clave JSON** para esa cuenta de servicio y descargarla. Ahí están `client_email` y `private_key`.
4. En Google Drive, compartir (botón "Compartir") las carpetas `Fotos` y `Testimonios` con el correo de la cuenta de servicio (termina en `@....iam.gserviceaccount.com`), como **Lector**. Solo esas dos carpetas — así, aunque alguien intente pedir un archivo de otra carpeta por la API, Google lo bloquea porque la cuenta de servicio no tiene acceso.
5. En Vercel → el proyecto → Settings → Environment Variables, crear:
   - `GOOGLE_SERVICE_ACCOUNT_EMAIL` = el `client_email` del JSON.
   - `GOOGLE_SERVICE_ACCOUNT_KEY` = el `private_key` del JSON (tal cual, con los `\n`).
   - `DRIVE_FOTOS_FOLDER_ID` = `1X6x-sYfZF8P1Gd02FyRgA9X2ANChigA9`
   - `DRIVE_TESTIMONIOS_FOLDER_ID` = `1x0cadE905p-jIuImfj0nG--kC9oSqtM2`
   - Aplicar a Production y Preview, y volver a desplegar.
6. Verificar abriendo `/api/gallery` y `/api/testimonios` en el navegador — deben devolver JSON con `"ready": true` y las fotos/testimonios encontrados.

Dentro de `Fotos`, organiza las subcarpetas como prefieras (por torneo, por árbitro, como sea más cómodo para el equipo) — cada subcarpeta directa se agrupa sola en la galería usando su propio nombre como etiqueta. Solo fotos ahí adentro; nada de hojas de cálculo, contratos ni información de contabilidad, para que no termine expuesto por accidente en la web pública.

Dentro de `Testimonios`, dos subcarpetas fijas: `Texto` (capturas de pantalla de WhatsApp) y `Audio` (notas de voz, cualquier formato de audio común como `.ogg`, `.mp3`, `.m4a`).

No hace falta redesplegar cada vez que se sube una foto o un testimonio nuevo: la web los lee en vivo (con una caché corta de 5 minutos) directamente de Drive.

## 6. Veedores: marcador, tarjetas y multas

Hay una segunda pantalla, `veedor.html`, con acceso completamente aparte del panel administrativo: cada veedor entra con su propio correo y contraseña y **solo ve los partidos que un administrador le asignó** (nunca los demás partidos, ni la plata del negocio). Esto lo hace la base de datos misma (Row Level Security en Supabase), no la aplicación — así que es seguro aunque alguien intente forzarlo desde el navegador.

Qué puede hacer un veedor desde su celular, por cada partido asignado:
- Ver cuánta plata debe reunir ese día (según lo acordado por partido).
- Anotar el marcador final.
- Registrar las tarjetas: a quién, de qué equipo, amarilla o roja. La multa se calcula sola (según la tarifa del torneo/categoría, o $5.000 amarilla / $10.000 roja por defecto si el partido no tiene categoría) — no hay que escribirla.
- Marcar una tarjeta como pagada cuando el jugador cancela la multa.

Qué ve el administrador (pestaña **Veedores** del panel):
- La lista de veedores, con cuántos partidos tiene cada uno.
- Un reporte de **novedades pendientes de pago**: todas las tarjetas de todos los partidos que todavía no se han pagado, con quién, de qué partido y cuánto — para saber, antes de la siguiente fecha, quién tiene que pagar para poder jugar.
- Puede marcar cualquier tarjeta como pagada también (por si el jugador le paga a él directamente en vez de al veedor).

Cómo crear un veedor nuevo (ya no hace falta tocar Supabase a mano):
1. En el panel administrativo, ir a **Veedores → + Agregar veedor**.
2. Escribir su nombre, teléfono y un correo (puede ser cualquiera al que tenga acceso, no necesita ser Gmail).
3. El sistema crea el usuario y muestra una contraseña generada una sola vez — cópiala y compártela por WhatsApp junto con el enlace a `veedor.html`.
4. El veedor entra a `veedor.html` con ese correo y esa contraseña.

Para que un veedor vea un partido, hay que asignárselo desde el formulario **Nuevo partido** (sección "Veedor"), igual que se asigna el árbitro.
