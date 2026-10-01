# Puesta en producción — landing de Silbatazo

Este repositorio es solo la landing pública (`index.html`), servida en **`silbatazo.com`** desde el proyecto de Vercel **`arbi-app-frontend`** (nombre heredado, no se renombró). Framework Preset "Other" (sitio estático, sin build), conectado por Git — cada `git push` a `main` despliega solo.

El panel administrativo (torneos, partidos, liquidaciones, etc.) ya **no vive en este repo**: es un proyecto Next.js + Supabase aparte, en `administracion.silbatazo.com`.

## Galería y testimonios automáticos desde Google Drive

La landing tiene dos secciones (`#galeria` y `#testimonios`) que se llenan solas leyendo carpetas de Google Drive, usando tres funciones serverless en `/api` (`gallery.js`, `testimonios.js`, `media.js`). Para activarlas hace falta una cuenta de servicio de Google con acceso de **solo lectura** a exactamente dos carpetas: `Fotos` y `Testimonios`. Nunca se le da acceso a `Documentos` (ahí vive información que no debe quedar pública).

Pasos (requieren la consola de Google Cloud y el dashboard de Vercel):

1. En [Google Cloud Console](https://console.cloud.google.com), crear un proyecto (o usar uno existente) y habilitar la **Google Drive API**.
2. Crear una **cuenta de servicio** (IAM & Admin → Service Accounts). No necesita ningún rol de proyecto.
3. Generar una **clave JSON** para esa cuenta de servicio y descargarla. Ahí están `client_email` y `private_key`.
4. En Google Drive, compartir las carpetas `Fotos` y `Testimonios` con el correo de la cuenta de servicio (termina en `@....iam.gserviceaccount.com`), como **Lector**.
5. En Vercel → el proyecto `arbi-app-frontend` → Settings → Environment Variables, crear:
   - `GOOGLE_SERVICE_ACCOUNT_EMAIL` = el `client_email` del JSON.
   - `GOOGLE_SERVICE_ACCOUNT_KEY` = el `private_key` del JSON (tal cual, con los `\n`).
   - `DRIVE_FOTOS_FOLDER_ID` = `1X6x-sYfZF8P1Gd02FyRgA9X2ANChigA9`
   - `DRIVE_TESTIMONIOS_FOLDER_ID` = `1x0cadE905p-jIuImfj0nG--kC9oSqtM2`
   - Aplicar a Production y Preview, y volver a desplegar.
6. Verificar abriendo `/api/gallery` y `/api/testimonios` en el navegador — deben devolver JSON con `"ready": true` y las fotos/testimonios encontrados.

Dentro de `Fotos`, cada subcarpeta directa se agrupa sola en la galería usando su propio nombre como etiqueta. Solo fotos ahí adentro; nada de hojas de cálculo, contratos ni información de contabilidad.

Dentro de `Testimonios`, dos subcarpetas fijas: `Texto` (capturas de pantalla de WhatsApp) y `Audio` (notas de voz).

No hace falta redesplegar cada vez que se sube una foto o un testimonio nuevo: la web los lee en vivo (con una caché corta de 5 minutos) directamente de Drive.
