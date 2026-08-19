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
