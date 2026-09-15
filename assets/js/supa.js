// Silbatazo — cliente de Supabase compartido entre admin.html y veedor.html.
// Este sitio no tiene paso de build: la config pública (URL + anon key)
// se pide a /api/config, que la lee de las variables de entorno en Vercel.
// La anon key de Supabase está pensada para ser pública — la seguridad de
// verdad vive en las políticas RLS de la base de datos, no en esconder esta
// llave.
window.SilbatazoAuth = (function () {
  let clientPromise = null;

  function getClient() {
    if (!clientPromise) {
      clientPromise = fetch('/api/config')
        .then((r) => r.json())
        .then((cfg) => {
          if (!cfg.ready) {
            throw new Error('Supabase todavía no está conectado (faltan SUPABASE_URL / SUPABASE_ANON_KEY en Vercel).');
          }
          return window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
        });
    }
    return clientPromise;
  }

  async function currentSession() {
    const client = await getClient();
    const { data } = await client.auth.getSession();
    return data.session || null;
  }

  async function signIn(email, password) {
    const client = await getClient();
    const { error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
  }

  async function signOut() {
    const client = await getClient();
    await client.auth.signOut();
  }

  async function myProfile() {
    const session = await currentSession();
    if (!session) return null;
    const client = await getClient();
    const { data, error } = await client.from('profiles').select('*').eq('id', session.user.id).single();
    if (error) return null;
    return data;
  }

  // Exige una sesión con el rol indicado ('admin' o 'veedor'). Si no hay
  // sesión o el rol no coincide, muestra una pantalla de login de pantalla
  // completa y no resuelve la promesa hasta que el login sea correcto
  // (en ese punto recarga la página, que es lo más simple y predecible).
  function requireRole(role, opts) {
    opts = opts || {};
    return new Promise((resolve) => {
      myProfile()
        .then((profile) => {
          if (profile && profile.role === role) {
            getClient().then((client) => resolve({ client: client, profile: profile }));
            return;
          }
          showLogin(role, opts, Boolean(profile));
        })
        .catch((err) => {
          showConfigError(err && err.message ? err.message : 'No se pudo conectar con el servidor.');
        });
    });
  }

  function showConfigError(message) {
    if (document.getElementById('authOverlay')) return;
    const overlay = document.createElement('div');
    overlay.id = 'authOverlay';
    overlay.style.cssText = 'position:fixed;inset:0;background:#06090f;color:#fff;display:grid;place-items:center;z-index:9999;font-family:Barlow,Arial,sans-serif;padding:18px;text-align:center';
    overlay.innerHTML =
      '<div style="max-width:420px">' +
        '<div style="font:900 1.4rem \'Barlow Condensed\',sans-serif;text-transform:uppercase;color:#ffbe2c;margin-bottom:10px">Sin conexión con el servidor</div>' +
        '<p style="color:#aeb4bf;font-size:.95rem">' + message + '</p>' +
      '</div>';
    document.body.appendChild(overlay);
  }

  // Los veedores entran con un usuario (no todos tienen correo), no con
  // email — por dentro sigue siendo un login de Supabase Auth con un
  // correo sintético que nunca se le muestra a nadie. Debe coincidir con
  // VEEDOR_EMAIL_DOMAIN en api/create-user.js.
  var VEEDOR_EMAIL_DOMAIN = 'veedores.silbatazo.local';

  function showLogin(role, opts, hadWrongRoleSession) {
    if (document.getElementById('authOverlay')) return;
    var isVeedor = role === 'veedor';
    var loginLabel = isVeedor ? 'Usuario' : 'Correo';
    var loginInputType = isVeedor ? 'text' : 'email';
    var loginHint = isVeedor ? 'Entra con el usuario y la contraseña que te dieron.' : 'Entra con el correo y la contraseña que te dieron.';
    const overlay = document.createElement('div');
    overlay.id = 'authOverlay';
    overlay.style.cssText = 'position:fixed;inset:0;background:#06090f;color:#fff;display:grid;place-items:center;z-index:9999;font-family:Barlow,Arial,sans-serif;padding:18px';
    overlay.innerHTML =
      '<form id="authForm" style="width:min(360px,100%);background:#10151d;border-radius:14px;padding:32px 26px;text-align:center">' +
        (opts.logoSrc ? '<img src="' + opts.logoSrc + '" alt="Silbatazo" style="width:150px;margin:0 auto 18px;display:block">' : '') +
        '<h1 style="font:900 1.5rem/1.2 \'Barlow Condensed\',Impact,sans-serif;text-transform:uppercase;margin:0 0 6px">' + (opts.title || 'Iniciar sesión') + '</h1>' +
        '<p style="color:#aeb4bf;font-size:.9rem;margin:0 0 22px">' + loginHint + '</p>' +
        '<div style="display:grid;gap:14px;text-align:left">' +
          '<label style="font-size:.78rem;font-weight:800;text-transform:uppercase;color:#8c8f95">' + loginLabel +
            '<input id="authEmail" type="' + loginInputType + '" required autocomplete="username" style="width:100%;margin-top:7px;padding:14px;border-radius:9px;border:1px solid #2a3340;background:#151c26;color:#fff;font-size:1.1rem;box-sizing:border-box">' +
          '</label>' +
          '<label style="font-size:.78rem;font-weight:800;text-transform:uppercase;color:#8c8f95">Contraseña' +
            '<input id="authPassword" type="password" required autocomplete="current-password" style="width:100%;margin-top:7px;padding:14px;border-radius:9px;border:1px solid #2a3340;background:#151c26;color:#fff;font-size:1.1rem;box-sizing:border-box">' +
          '</label>' +
        '</div>' +
        '<p id="authError" style="color:#ff615b;font-size:.9rem;min-height:1.3em;margin:16px 0 0;font-weight:700"></p>' +
        '<button type="submit" style="margin-top:10px;width:100%;border:0;border-radius:9px;padding:17px;min-height:54px;background:#00d08a;color:#06090f;font-weight:900;font-size:1.1rem;cursor:pointer">Entrar</button>' +
      '</form>';
    document.body.appendChild(overlay);

    const errorEl = overlay.querySelector('#authError');
    if (hadWrongRoleSession) {
      errorEl.textContent = role === 'admin'
        ? 'Ese usuario no tiene acceso de administrador.'
        : 'Ese usuario no tiene acceso de veedor.';
    }

    overlay.querySelector('#authForm').addEventListener('submit', async function (e) {
      e.preventDefault();
      errorEl.textContent = '';
      const raw = overlay.querySelector('#authEmail').value.trim();
      const email = isVeedor ? (raw.toLowerCase().replace(/\s+/g, '') + '@' + VEEDOR_EMAIL_DOMAIN) : raw;
      const password = overlay.querySelector('#authPassword').value;
      const btn = overlay.querySelector('button[type="submit"]');
      btn.disabled = true;
      btn.textContent = 'Entrando…';
      try {
        if (hadWrongRoleSession) await signOut();
        await signIn(email, password);
        window.location.reload();
      } catch (err) {
        errorEl.textContent = 'Usuario o contraseña incorrectos.';
        btn.disabled = false;
        btn.textContent = 'Entrar';
      }
    });
  }

  return {
    getClient: getClient,
    currentSession: currentSession,
    signIn: signIn,
    signOut: signOut,
    myProfile: myProfile,
    requireRole: requireRole,
  };
})();
