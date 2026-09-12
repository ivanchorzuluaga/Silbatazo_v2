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
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
3. Aplicarlas a Production y Preview.
4. Hacer un nuevo despliegue; los cambios de variables no afectan despliegues anteriores.

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

La interfaz visual está preparada y el esquema productivo está creado. Para reemplazar definitivamente el almacenamiento local por Supabase se necesitan la URL pública y la clave `anon` del proyecto. Estas claves se configuran en Vercel; nunca se debe usar la clave `service_role` en el navegador.

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

Estructura esperada dentro de `Fotos` (cada subcarpeta se agrupa sola en la web por su nombre):

```
Fotos/
  Arbitros/
  Fotos Profes/ (dentro de Listas Silbatazo)
  Fotos Varias de todo/
  Torneo Alegria/
  Torneo San felix/
  Torneo Altavista/
  Torneo Cordeca/
  Torneo Villaterra/
  TORNEO - Primavera/
```

Y dentro de `Testimonios`, dos subcarpetas fijas: `Texto` (capturas de pantalla de WhatsApp) y `Audio` (notas de voz, cualquier formato de audio común como `.ogg`, `.mp3`, `.m4a`).

No hace falta redesplegar cada vez que se sube una foto o un testimonio nuevo: la web los lee en vivo (con una caché corta de 5 minutos) directamente de Drive.
