# Puesta en producción de Silbatazo Gestión

## Arquitectura recomendada

- **Frontend y dominio:** conservar el proyecto actual de Vercel.
- **Base de datos y autenticación:** Supabase (PostgreSQL + Auth).
- **Código:** repositorio privado `ivanchorzuluaga/Silbatazo_v2`.
- **Usuarios:** solo los tres administradores, creados manualmente.

## 1. Crear Supabase

1. Crear un proyecto en Supabase, eligiendo una región cercana.
2. Guardar la contraseña de base de datos en un gestor de contraseñas.
3. Abrir **SQL Editor**, pegar `supabase/schema.sql` y ejecutarlo.
4. En **Authentication → Users**, crear los tres usuarios administrativos.
5. Copiar el UUID de cada usuario y crear su perfil:

```sql
insert into public.profiles (id, full_name)
values ('UUID-DEL-USUARIO', 'Nombre del administrador');
```

6. En **Authentication → URL Configuration**, agregar el dominio de producción de Vercel y sus URLs de redirección.

## 2. Conectar Vercel

1. Importar o actualizar el proyecto usando el repositorio de GitHub.
2. En **Settings → Environment Variables**, crear:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY` (Settings → API → "service_role" en Supabase — **nunca** se usa en el navegador; solo la leen las funciones serverless de `/api`, como `create-veedor.js`)
3. Aplicarlas a Production y Preview.
4. Hacer un nuevo despliegue; los cambios de variables no afectan despliegues anteriores.

Nota: este sitio no tiene paso de build (no Vite), así que estas variables no se inyectan en el HTML directamente. `admin.html` y `veedor.html` piden la URL y la anon key al cargar a través de `/api/config` (una función serverless que simplemente las lee del entorno) — por eso el prefijo `VITE_` de versiones anteriores de este archivo ya no aplica.

## 3. Antes de usar datos reales

- Confirmar que un usuario sin sesión no puede leer ni modificar tablas.
- Probar creación y edición de clientes, árbitros, torneos y partidos.
- Probar un partido con central y dos asistentes.
- Verificar el ejemplo financiero 100.000 / 90.000 / 50.000 / 50.000 / 40.000.
- Configurar alertas de uso y revisar crecimiento de la base mensualmente.
- Exportar una copia antes de cambios grandes mientras se use el plan gratuito.

## 4. Paso recomendado de planes

1. Desarrollo y pruebas: Supabase Free.
2. Operación diaria: Supabase Pro para evitar pausas y contar con respaldos automáticos.
3. Mantener Vercel actual mientras el consumo siga dentro de su plan.

## Pendiente de credenciales

`admin.html` y `veedor.html` ya están escritos para hablar directamente con Supabase (ya no usan almacenamiento local del navegador). Para que funcionen en vivo solo falta que exista el proyecto de Supabase real y que sus llaves estén puestas en Vercel (paso 1 y 2 de arriba) — mientras eso no esté, ambas páginas muestran una pantalla de "sin conexión con el servidor" en vez de fallar en silencio.

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
- Registrar las tarjetas: a quién, de qué equipo, amarilla o roja. La multa se calcula sola ($5.000 amarilla, $10.000 roja) — no hay que escribirla.
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
