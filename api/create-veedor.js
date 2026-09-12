// POST /api/create-veedor
// Crea el login de un veedor nuevo: usuario en Supabase Auth, su perfil
// (profiles.role = 'veedor') y su ficha de veedor (observers). Solo lo
// puede ejecutar un administrador con sesión válida — se verifica su
// token contra Supabase antes de hacer nada (ver paso 1 más abajo).
//
// Variables de entorno requeridas (Vercel, nunca en el repo):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
//
// IMPORTANTE DE SEGURIDAD: SUPABASE_SERVICE_ROLE_KEY salta todas las
// reglas de RLS — por eso esta función jamás la manda al navegador, y
// por eso el primer paso confirma "quién llama" usando SU PROPIO token
// (no la service key), para que las políticas RLS decidan si es admin.
//
// Body esperado: { name, phone?, email, password? }
// Si no mandas password, se genera una fácil de dictar por WhatsApp.
// Respuesta: { ok:true, email, password } — el admin se la comparte al
// veedor (puede cambiarla después; eso no lo cubre esta función todavía).

function randomPassword() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sin 0/O/1/I/L, para no confundir al dictarla
  let out = '';
  for (let i = 0; i < 8; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

async function supabaseRestInsert(url, serviceKey, table, row) {
  const r = await fetch(`${url}/rest/v1/${table}`, {
    method: 'POST',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(row),
  });
  const data = await r.json();
  if (!r.ok) throw new Error((data && (data.message || data.msg)) || `No se pudo guardar en ${table}.`);
  return data;
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido.' });
    return;
  }

  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anonKey || !serviceKey) {
    res.status(500).json({ ok: false, error: 'Supabase todavía no está configurado en el servidor.' });
    return;
  }

  try {
    // 1) ¿Quién llama, y es admin? Se valida con SU token contra Supabase
    //    (la tabla profiles solo se puede leer si eres tú mismo o eres
    //    admin — ver supabase/schema.sql — así que esto es confiable).
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (!token) {
      res.status(401).json({ ok: false, error: 'Falta iniciar sesión.' });
      return;
    }
    const meRes = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
    });
    if (!meRes.ok) {
      res.status(401).json({ ok: false, error: 'Sesión inválida o vencida.' });
      return;
    }
    const me = await meRes.json();
    const profileRes = await fetch(`${url}/rest/v1/profiles?id=eq.${me.id}&select=role`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
    });
    const profileRows = profileRes.ok ? await profileRes.json() : [];
    if (!profileRows.length || profileRows[0].role !== 'admin') {
      res.status(403).json({ ok: false, error: 'Solo un administrador puede crear veedores.' });
      return;
    }

    // 2) Datos del veedor nuevo
    const body = req.body && typeof req.body === 'object' ? req.body : JSON.parse(req.body || '{}');
    const name = (body.name || '').trim();
    const phone = (body.phone || '').trim();
    const email = (body.email || '').trim().toLowerCase();
    const password = (body.password || '').trim() || randomPassword();
    if (!name || !email) {
      res.status(400).json({ ok: false, error: 'Falta el nombre o el correo del veedor.' });
      return;
    }

    // 3) Crear el usuario en Supabase Auth (solo posible con la service key)
    const createUserRes = await fetch(`${url}/auth/v1/admin/users`, {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password, email_confirm: true }),
    });
    const created = await createUserRes.json();
    if (!createUserRes.ok) {
      const msg = created && (created.msg || created.error_description || created.message);
      res.status(400).json({ ok: false, error: msg || 'No se pudo crear el usuario.' });
      return;
    }
    const userId = created.id || (created.user && created.user.id);

    // 4) Perfil + ficha de veedor (con service key, sin pasar por RLS)
    await supabaseRestInsert(url, serviceKey, 'profiles', { id: userId, full_name: name, role: 'veedor' });
    await supabaseRestInsert(url, serviceKey, 'observers', { profile_id: userId, name, phone: phone || null });

    res.status(200).json({ ok: true, email, password });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err && err.message ? err.message : err) });
  }
};
