#!/bin/bash
# ============================================================
# DESCARTADO — no ejecutar. Este script creaba desde cero un proyecto
# Next.js aparte (silbatazo-admin/). Se decidió extender en su lugar el
# sistema real ya en producción (admin.html/veedor.html + Supabase, sin
# build step). Ver CLAUDE.md para el contexto vigente. Se deja el archivo
# solo por si se quiere rescatar texto de los prompts.
# ============================================================
# SILBATAZO — Script de setup del proyecto
# Ejecutar desde la carpeta donde quieres crear el proyecto
# ============================================================

set -e

echo "🟢 Creando proyecto Silbatazo Admin..."

# 1. Crear proyecto Next.js
npx create-next-app@latest silbatazo-admin \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --src-dir \
  --import-alias "@/*" \
  --no-git

cd silbatazo-admin

# 2. Instalar dependencias
echo "📦 Instalando dependencias..."

npm install \
  @supabase/supabase-js \
  @supabase/ssr \
  @radix-ui/react-dialog \
  @radix-ui/react-dropdown-menu \
  @radix-ui/react-select \
  @radix-ui/react-toast \
  @radix-ui/react-tabs \
  @radix-ui/react-label \
  @radix-ui/react-switch \
  @radix-ui/react-badge \
  lucide-react \
  xlsx \
  date-fns \
  clsx \
  tailwind-merge \
  class-variance-authority \
  sonner

npm install -D \
  @types/node \
  supabase

# 3. Inicializar shadcn/ui
echo "🎨 Configurando shadcn/ui..."
npx shadcn@latest init --defaults

# Instalar componentes de shadcn que vamos a usar
npx shadcn@latest add button input label card table badge select dialog toast tabs switch form

# 4. Crear estructura de carpetas
echo "📁 Creando estructura de carpetas..."

mkdir -p src/app/\(admin\)/dashboard
mkdir -p src/app/\(admin\)/torneos
mkdir -p src/app/\(admin\)/arbitros
mkdir -p src/app/\(admin\)/veedores
mkdir -p src/app/\(admin\)/canchas
mkdir -p src/app/\(admin\)/partidos
mkdir -p src/app/\(admin\)/asignaciones
mkdir -p src/app/\(admin\)/programacion
mkdir -p src/app/\(admin\)/liquidaciones
mkdir -p src/app/\(veedor\)/partidos
mkdir -p src/app/auth
mkdir -p src/app/api/veedor
mkdir -p src/app/api/partidos
mkdir -p src/components/ui
mkdir -p src/components/admin
mkdir -p src/components/veedor
mkdir -p src/lib/queries
mkdir -p src/lib/utils
mkdir -p src/types
mkdir -p src/actions
mkdir -p supabase/migrations

# 5. Crear archivo de tipos
cat > src/types/index.ts << 'EOF'
// ============================================================
// TIPOS PRINCIPALES — Silbatazo Admin
// ============================================================

export type TipoServicio = 'completo' | 'solo_arbitraje'
export type EstadoPartido = 'programado' | 'en_curso' | 'finalizado' | 'por_w'
export type TipoTarjeta = 'amarilla' | 'roja'
export type EstadoLiquidacion = 'pendiente' | 'cerrada'

export interface Cancha {
  id: string
  nombre: string
  activa: boolean
  created_at: string
}

export interface Arbitro {
  id: string
  nombre: string
  telefono?: string
  activo: boolean
  created_at: string
}

export interface Veedor {
  id: string
  nombre: string
  telefono?: string
  es_arbitro: boolean
  arbitro_id?: string
  activo: boolean
  access_token: string
  created_at: string
}

export interface Torneo {
  id: string
  nombre: string
  activo: boolean
  requiere_veedor: boolean
  tiene_tarjetas: boolean
  split_veedor_silbatazo_pct: number
  split_veedor_torneo_pct: number
  created_at: string
  // Relaciones
  categorias?: TorneoCategoria[]
  equipos?: Equipo[]
}

export interface TorneoCategoria {
  id: string
  torneo_id: string
  nombre: string
  created_at: string
  // Relaciones
  tarifa?: Tarifa
}

export interface Tarifa {
  id: string
  torneo_id: string
  categoria_id: string
  valor_por_equipo: number
  valor_arbitro: number
  valor_veedor: number
  valor_silbatazo: number
  valor_torneo: number
  valor_amarilla: number
  silbatazo_amarilla: number
  torneo_amarilla: number
  valor_roja: number
  silbatazo_roja: number
  torneo_roja: number
  created_at: string
}

export interface Equipo {
  id: string
  torneo_id: string
  nombre: string
  activo: boolean
  created_at: string
}

export interface Partido {
  id: string
  torneo_id: string
  categoria_id: string
  cancha_id?: string
  fecha: string
  hora: string
  equipo_local_id: string
  equipo_visitante_id: string
  arbitro_id?: string
  veedor_id?: string
  arbitro_es_veedor: boolean
  tipo_servicio: TipoServicio
  estado: EstadoPartido
  equipo_w_id?: string
  goles_local?: number
  goles_visitante?: number
  novedades?: string
  created_at: string
  updated_at: string
  // Relaciones expandidas
  torneo?: Torneo
  categoria?: TorneoCategoria
  cancha?: Cancha
  equipo_local?: Equipo
  equipo_visitante?: Equipo
  arbitro?: Arbitro
  veedor?: Veedor
  tarjetas?: Tarjeta[]
}

export interface Tarjeta {
  id: string
  partido_id: string
  equipo_id: string
  jugador_nombre: string
  tipo: TipoTarjeta
  minuto?: number
  valor_cobro: number
  valor_silbatazo: number
  valor_torneo: number
  pagada: boolean
  pagada_en_partido_id?: string
  registrada_por_veedor_id?: string
  created_at: string
  // Relaciones
  equipo?: Equipo
  partido?: Partido
}

export interface Liquidacion {
  id: string
  veedor_id: string
  fecha_inicio: string
  fecha_fin: string
  num_partidos: number
  total_recaudado: number
  total_pagado_arbitros: number
  total_tarjetas_cobradas: number
  total_veedor: number
  total_silbatazo: number
  total_torneo: number
  ajuste_por_w: number
  estado: EstadoLiquidacion
  notas?: string
  created_at: string
  cerrada_at?: string
  // Relaciones
  veedor?: Veedor
}

// Para importar desde Excel
export interface PartidoImport {
  fecha: string        // "2024-03-15"
  hora: string         // "10:00"
  cancha: string       // nombre de cancha
  equipo_local: string
  equipo_visitante: string
  categoria: string    // "Sub-14"
}

// Resumen para vista del veedor
export interface ResumenPartidoVeedor {
  partido: Partido
  a_cobrar_por_equipo: number
  total_a_cobrar: number
  ganancia_veedor: number
  transferir_silbatazo: number
  transferir_torneo: number
  tarjetas_pendientes: TarjetaPendiente[]
}

export interface TarjetaPendiente {
  equipo_nombre: string
  jugador_nombre: string
  tipo: TipoTarjeta
  valor_a_cobrar: number
  valor_silbatazo: number
  valor_torneo: number
}
EOF

echo "✅ Tipos creados"

# 6. Crear cliente de Supabase
mkdir -p src/lib/supabase

cat > src/lib/supabase/client.ts << 'EOF'
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
EOF

cat > src/lib/supabase/server.ts << 'EOF'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {}
        },
      },
    }
  )
}
EOF

cat > src/lib/supabase/admin.ts << 'EOF'
// Cliente con service_role — solo usar en Server Actions y API routes
import { createClient } from '@supabase/supabase-js'

export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )
}
EOF

echo "✅ Clientes Supabase creados"

# 7. Utilidades
cat > src/lib/utils/format.ts << 'EOF'
// Formatear pesos colombianos
export function formatCOP(value: number): string {
  return new Intl.NumberFormat('es-CO', {
    style: 'currency',
    currency: 'COP',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value)
}

// Formatear fecha legible
export function formatFecha(fecha: string): string {
  const date = new Date(fecha + 'T00:00:00')
  return date.toLocaleDateString('es-CO', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
}

// Formatear hora
export function formatHora(hora: string): string {
  return hora.substring(0, 5) // "10:00"
}

// Generar texto de WhatsApp para árbitro
export function generarTextoArbitro(nombre: string, partidos: any[]): string {
  let texto = `⚽ *PROGRAMACIÓN SILBATAZO*\n`
  texto += `*Árbitro:* ${nombre}\n\n`

  partidos.forEach((p, i) => {
    texto += `*Partido ${i + 1}*\n`
    texto += `📅 ${formatFecha(p.fecha)} — ${formatHora(p.hora)}\n`
    texto += `📍 ${p.cancha?.nombre ?? 'Cancha por confirmar'}\n`
    texto += `🏆 ${p.torneo?.nombre} | ${p.categoria?.nombre}\n`
    texto += `⚔️ ${p.equipo_local?.nombre} vs ${p.equipo_visitante?.nombre}\n`
    texto += `💵 Honorarios: ${formatCOP(p.tarifa?.valor_arbitro ?? 0)}\n\n`
  })

  texto += `_Cualquier novedad comunicarse con Silbatazo_ 🟢`
  return texto
}

// Generar texto de WhatsApp para veedor
export function generarTextoVeedor(nombre: string, resumenes: any[]): string {
  let texto = `💼 *PROGRAMACIÓN VEEDOR — SILBATAZO*\n`
  texto += `*Veedor:* ${nombre}\n\n`

  resumenes.forEach((r, i) => {
    const p = r.partido
    texto += `*Partido ${i + 1}*\n`
    texto += `📅 ${formatFecha(p.fecha)} — ${formatHora(p.hora)}\n`
    texto += `📍 ${p.cancha?.nombre ?? 'Por confirmar'}\n`
    texto += `🏆 ${p.torneo?.nombre} | ${p.categoria?.nombre}\n`
    texto += `⚔️ ${p.equipo_local?.nombre} vs ${p.equipo_visitante?.nombre}\n`
    texto += `💰 Cobrar: ${formatCOP(r.a_cobrar_por_equipo)} × 2 equipos\n`
    texto += `👤 Tu ganancia: ${formatCOP(r.ganancia_veedor)}\n`
    texto += `➡️ Transferir Silbatazo: ${formatCOP(r.transferir_silbatazo)}\n`
    if (r.transferir_torneo > 0) {
      texto += `➡️ Transferir Torneo: ${formatCOP(r.transferir_torneo)}\n`
    }
    if (r.tarjetas_pendientes.length > 0) {
      texto += `⚠️ *Novedades:*\n`
      r.tarjetas_pendientes.forEach((t: any) => {
        texto += `  - ${t.equipo_nombre}: ${t.jugador_nombre} debe ${formatCOP(t.valor_a_cobrar)} (${t.tipo})\n`
      })
    }
    texto += '\n'
  })

  texto += `_Silbatazo — Arbitraje profesional_ 🟢`
  return texto
}
EOF

echo "✅ Utilidades creadas"

# 8. Variables de entorno
cat > .env.local << 'EOF'
NEXT_PUBLIC_SUPABASE_URL=tu_url_aqui
NEXT_PUBLIC_SUPABASE_ANON_KEY=tu_anon_key_aqui
SUPABASE_SERVICE_ROLE_KEY=tu_service_role_key_aqui
EOF

cat > .env.example << 'EOF'
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
EOF

# 9. .gitignore additions
echo ".env.local" >> .gitignore

echo ""
echo "✅ ¡Proyecto Silbatazo Admin listo!"
echo ""
echo "📋 PRÓXIMOS PASOS:"
echo "1. Crear proyecto en supabase.com"
echo "2. Copiar las keys en .env.local"
echo "3. Ejecutar el SQL de migrations/001_initial_schema.sql en Supabase"
echo "4. npm run dev"
echo ""
echo "📁 Estructura creada en: silbatazo-admin/"
