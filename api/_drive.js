// Utilidades compartidas para hablar con la API de Google Drive usando una
// cuenta de servicio, SIN depender de la librería googleapis (cero
// dependencias npm, consistente con el resto del sitio que no tiene build).
//
// Variables de entorno requeridas (se configuran en Vercel, nunca en el repo):
//   GOOGLE_SERVICE_ACCOUNT_EMAIL   -> el "client_email" del JSON de la cuenta de servicio
//   GOOGLE_SERVICE_ACCOUNT_KEY     -> el "private_key" del JSON (con los \n literales está bien)
//   DRIVE_FOTOS_FOLDER_ID          -> id de la carpeta "Fotos" en Drive
//   DRIVE_TESTIMONIOS_FOLDER_ID    -> id de la carpeta "Testimonios" en Drive
//
// IMPORTANTE DE SEGURIDAD: la cuenta de servicio SOLO debe tener acceso
// (compartido desde Drive) a las carpetas "Fotos" y "Testimonios". Nunca
// compartas "Documentos" ni ninguna carpeta con información financiera,
// legal o de accesos/contraseñas. La API de Drive ya bloquea por sí sola
// cualquier archivo fuera de lo compartido, así que esto es la única
// barrera real: lo que no se comparte, no se puede leer ni filtrar.

const crypto = require('crypto');

let cachedToken = null; // { token, expiresAt }

function base64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function getAccessToken() {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30000) {
    return cachedToken.token;
  }

  const email = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;
  const key = (process.env.GOOGLE_SERVICE_ACCOUNT_KEY || '').replace(/\\n/g, '\n');
  if (!email || !key) {
    throw new Error('Faltan GOOGLE_SERVICE_ACCOUNT_EMAIL / GOOGLE_SERVICE_ACCOUNT_KEY en las variables de entorno.');
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: email,
    scope: 'https://www.googleapis.com/auth/drive.readonly',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign(key).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const jwt = `${unsigned}.${signature}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`No se pudo autenticar con Google (token): ${res.status} ${text}`);
  }

  const data = await res.json();
  cachedToken = { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return cachedToken.token;
}

async function driveFetch(path, params) {
  const token = await getAccessToken();
  const url = new URL(`https://www.googleapis.com/drive/v3/${path}`);
  Object.entries(params || {}).forEach(([k, v]) => url.searchParams.set(k, v));
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  return res;
}

// Lista los hijos directos (archivos y carpetas) de una carpeta.
async function listChildren(folderId) {
  let files = [];
  let pageToken;
  do {
    const res = await driveFetch('files', {
      q: `'${folderId}' in parents and trashed = false`,
      fields: 'nextPageToken, files(id, name, mimeType, modifiedTime)',
      pageSize: '200',
      ...(pageToken ? { pageToken } : {}),
    });
    if (!res.ok) throw new Error(`Drive files.list falló: ${res.status} ${await res.text()}`);
    const data = await res.json();
    files = files.concat(data.files || []);
    pageToken = data.nextPageToken;
  } while (pageToken);
  return files;
}

const FOLDER_MIME = 'application/vnd.google-apps.folder';

// Recorre una carpeta raíz y agrupa los archivos que no son carpetas por el
// nombre de su subcarpeta directa (una sola profundidad de agrupación,
// pensado para "Fotos/Arbitros/*.jpg", "Fotos/Torneo Alegria/*.jpg", etc).
async function listGroupedByFolder(rootId, { mimePrefix } = {}) {
  const top = await listChildren(rootId);
  const groups = [];
  for (const entry of top) {
    if (entry.mimeType === FOLDER_MIME) {
      const inner = await listChildren(entry.id);
      const items = inner.filter((f) => f.mimeType !== FOLDER_MIME && (!mimePrefix || f.mimeType.startsWith(mimePrefix)));
      if (items.length) {
        groups.push({ folder: entry.name, folderId: entry.id, items });
      }
    } else if (!mimePrefix || entry.mimeType.startsWith(mimePrefix)) {
      groups.push({ folder: null, folderId: rootId, items: [entry] });
    }
  }
  return groups;
}

async function streamFile(fileId, res) {
  const token = await getAccessToken();
  const metaRes = await driveFetch(`files/${fileId}`, { fields: 'mimeType, name' });
  if (!metaRes.ok) {
    res.status(metaRes.status).end('No encontrado o sin acceso.');
    return;
  }
  const meta = await metaRes.json();
  const url = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`;
  const fileRes = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!fileRes.ok) {
    res.status(fileRes.status).end('No se pudo leer el archivo.');
    return;
  }
  res.setHeader('Content-Type', meta.mimeType || 'application/octet-stream');
  res.setHeader('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800');
  const buf = Buffer.from(await fileRes.arrayBuffer());
  res.status(200).end(buf);
}

module.exports = { listChildren, listGroupedByFolder, streamFile, getAccessToken };
