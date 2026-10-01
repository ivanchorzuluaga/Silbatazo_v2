# Silbatazo — landing pública

Este repositorio es **solo la landing** (`index.html`, servida en `silbatazo.com`). El panel administrativo (torneos, partidos, árbitros, veedores, liquidaciones) se retiró de aquí — vivía en `admin.html`/`veedor.html` con una base de datos Supabase propia (proyecto `Silbatazo_v2`, ref `llilwqlqgbronvbsffav`, hoy pausada). Ambos se reemplazaron por un proyecto nuevo, Next.js + Supabase, en `administracion.silbatazo.com`.

## Qué queda en este repo
- `index.html` — la landing.
- `assets/` — imágenes y logos.
- `api/_drive.js`, `api/gallery.js`, `api/media.js`, `api/testimonios.js` — funciones serverless que leen Google Drive de solo lectura para las secciones "Galería" y "Testimonios" de la landing (ver `PRODUCTION.md` para cómo configurarlas).

## Stack
HTML + JS plano, sin paso de build (Framework Preset "Other" en Vercel). Deploy: proyecto de Vercel `arbi-app-frontend` (nombre heredado), dominio `silbatazo.com`, conectado por Git — cada `git push` a `main` despliega solo.

## Convenciones
Identidad visual y logos: ver `README.md`.
