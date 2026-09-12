// GET /api/config
// Config pública para inicializar el cliente de Supabase en el navegador
// (admin.html y veedor.html la piden al cargar). La anon key de Supabase
// está diseñada para ser pública — la seguridad real vive en las
// políticas RLS de la base de datos (ver supabase/schema.sql), no en
// esconder esta llave.
module.exports = async (req, res) => {
  const url = process.env.SUPABASE_URL || '';
  const anonKey = process.env.SUPABASE_ANON_KEY || '';
  res.setHeader('Cache-Control', 'private, max-age=60');
  res.status(200).json({
    ready: Boolean(url && anonKey),
    supabaseUrl: url,
    supabaseAnonKey: anonKey,
  });
};
