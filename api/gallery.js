const { listGroupedByFolder } = require('./_drive');

// GET /api/gallery
// Devuelve las fotos agrupadas por subcarpeta dentro de la carpeta "Fotos"
// de Drive, clasificadas en categorías simples para la web:
//   - torneos: subcarpetas cuyo nombre empieza por "torneo"
//   - arbitros: subcarpetas de árbitros / "profes"
//   - otras: el resto (fotos varias, etc.)
module.exports = async (req, res) => {
  try {
    const rootId = process.env.DRIVE_FOTOS_FOLDER_ID;
    if (!rootId) {
      res.status(200).json({ ready: false, reason: 'DRIVE_FOTOS_FOLDER_ID no configurado todavía.', categories: [] });
      return;
    }

    const groups = await listGroupedByFolder(rootId, { mimePrefix: 'image/' });

    const categorize = (name) => {
      const n = (name || '').toLowerCase();
      if (n.includes('torneo')) return 'torneos';
      if (n.includes('arbitro') || n.includes('árbitro') || n.includes('profe') || n.includes('lista')) return 'arbitros';
      return 'otras';
    };

    const categories = groups
      .filter((g) => g.folder) // solo carpetas con nombre (ignora sueltos en la raíz)
      .map((g) => ({
        folder: g.folder,
        category: categorize(g.folder),
        items: g.items.map((f) => ({ id: f.id, name: f.name, mimeType: f.mimeType })),
      }));

    res.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=3600');
    res.status(200).json({ ready: true, categories });
  } catch (err) {
    res.status(500).json({ ready: false, error: String(err && err.message ? err.message : err) });
  }
};
