const { listChildren } = require('./_drive');

// GET /api/testimonios
// Lee las subcarpetas "Texto" (capturas de pantalla de WhatsApp) y "Audio"
// (notas de voz) dentro de la carpeta "Testimonios" de Drive.
module.exports = async (req, res) => {
  try {
    const rootId = process.env.DRIVE_TESTIMONIOS_FOLDER_ID;
    if (!rootId) {
      res.status(200).json({ ready: false, reason: 'DRIVE_TESTIMONIOS_FOLDER_ID no configurado todavía.', texto: [], audio: [] });
      return;
    }

    const top = await listChildren(rootId);
    const textoFolder = top.find((f) => f.mimeType === 'application/vnd.google-apps.folder' && f.name.toLowerCase() === 'texto');
    const audioFolder = top.find((f) => f.mimeType === 'application/vnd.google-apps.folder' && f.name.toLowerCase() === 'audio');

    const [textoFiles, audioFiles] = await Promise.all([
      textoFolder ? listChildren(textoFolder.id) : [],
      audioFolder ? listChildren(audioFolder.id) : [],
    ]);

    const texto = textoFiles
      .filter((f) => f.mimeType.startsWith('image/'))
      .map((f) => ({ id: f.id, name: f.name, mimeType: f.mimeType }));

    const audio = audioFiles
      .filter((f) => f.mimeType.startsWith('audio/'))
      .map((f) => ({ id: f.id, name: f.name, mimeType: f.mimeType }));

    res.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=3600');
    res.status(200).json({ ready: true, texto, audio });
  } catch (err) {
    res.status(500).json({ ready: false, error: String(err && err.message ? err.message : err) });
  }
};
