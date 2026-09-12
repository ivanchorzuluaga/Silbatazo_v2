const { streamFile } = require('./_drive');

// GET /api/media?id=FILE_ID
// Sirve el contenido real (bytes) de una foto o audio de Drive.
// Seguro por diseño: la cuenta de servicio SOLO tiene acceso a lo que se le
// comparte explícitamente en Drive (Fotos y Testimonios), así que aunque
// alguien mande un id inventado, Google Drive responde 403/404 para
// cualquier archivo fuera de esas carpetas.
module.exports = async (req, res) => {
  const id = (req.query && req.query.id) || new URL(req.url, 'http://x').searchParams.get('id');
  if (!id) {
    res.status(400).end('Falta el parámetro id.');
    return;
  }
  try {
    await streamFile(id, res);
  } catch (err) {
    res.status(500).end(`Error: ${err && err.message ? err.message : err}`);
  }
};
