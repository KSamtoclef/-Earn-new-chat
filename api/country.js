export default function handler(request, response) {
  const raw = request.headers['x-vercel-ip-country'];
  const country = typeof raw === 'string' && /^[A-Z]{2}$/i.test(raw) ? raw.toUpperCase() : null;
  response.setHeader('Cache-Control', 'private, no-store');
  response.status(200).json({ country });
}
