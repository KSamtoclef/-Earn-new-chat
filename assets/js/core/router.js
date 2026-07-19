const publicRoutes = new Set(['/', '/register', '/login']);

export function currentRoute() {
  const raw = location.hash.replace(/^#/, '') || '/';
  return raw.startsWith('/') ? raw : `/${raw}`;
}

export function navigate(route, replace = false) {
  const target = `#${route}`;
  if (replace) history.replaceState(null, '', target); else location.hash = route;
}

export function isPublicRoute(route) { return publicRoutes.has(route); }
export function onRouteChange(handler) { window.addEventListener('hashchange', handler); return () => window.removeEventListener('hashchange', handler); }
