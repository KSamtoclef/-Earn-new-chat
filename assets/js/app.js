import { store } from './core/store.js';
import { currentRoute, isPublicRoute, navigate, onRouteChange } from './core/router.js';
import { getSession, logout, watchAuth } from './services/auth.js';
import { platform } from './services/platform.js';
import { renderAuth } from './features/auth-view.js';
import { renderHome } from './features/home-view.js';
import { renderTasks } from './features/tasks-view.js';
import { renderProgress } from './features/progress-view.js';
import { renderProfile } from './features/profile-view.js';

const root = document.getElementById('app');
const header = document.querySelector('[data-public-header]');
const nav = document.querySelector('[data-bottom-nav]');
const toastRegion = document.getElementById('toast-region');
let renderToken = 0;

function notify(message) {
  const item = document.createElement('div'); item.className = 'toast'; item.textContent = message;
  toastRegion.append(item); setTimeout(() => item.remove(), 3500);
}

function showLanding() {
  root.innerHTML = `<section class="page hero"><div class="flag-row"><span>🇺🇸</span><span>🇬🇧</span><span>🇨🇦</span><span>🇦🇺</span><span class="more">+6</span></div><div class="eyebrow">Meaningful conversations every day</div><h1>Chat, progress<br>and <em>earn</em></h1><p class="hero-copy">Continue real guided conversations, complete daily goals and build your five-day Earn Chat progress.</p><div class="hero-actions"><a class="button button-primary" href="#/register">Start Your Journey — Free →</a><a class="button button-secondary" href="#/login">I already have an account</a></div><div class="trust-row"><span>✓ Free to join</span><span>✓ Server-secured progress</span><span>✓ Resume anytime</span></div><article class="feature-strip"><strong>A different reason to return tomorrow</strong><p>Daily topics, streak milestones, partner memory and clear conversation completion.</p></article></section>`;
}

function showPlaceholder(route) {
  const title = route === '/tasks' ? 'Daily Tasks' : route === '/progress' ? 'Your Progress' : 'My Profile';
  root.innerHTML = `<section class="page"><div class="section-heading"><h2>${title}</h2></div><div class="empty-card">This screen is part of the next Stage 4 checkpoint. Your server state is already protected and preserved.</div></section>`;
}

async function ensureHome(token) {
  const cached = store.get().home;
  if (cached) return cached;
  const home = await platform.home();
  if (token !== renderToken) return null;
  store.set({ home });
  return home;
}

function setChrome(authenticated, route) {
  header.hidden = authenticated;
  nav.hidden = !authenticated;
  nav.querySelectorAll('[data-nav]').forEach((link) => link.classList.toggle('active', link.dataset.nav === route.slice(1)));
}

async function render() {
  const token = ++renderToken;
  const state = store.get();
  let route = currentRoute();
  if (!state.session && !isPublicRoute(route)) { navigate('/login', true); route = '/login'; }
  if (state.session && isPublicRoute(route)) { navigate('/home', true); route = '/home'; }
  store.set({ route });
  setChrome(Boolean(state.session), route);
  if (route === '/') return showLanding();
  if (route === '/login' || route === '/register') return renderAuth(root, route.slice(1), async () => { const session = await getSession(); store.set({ session, user: session?.user || null }); navigate('/home', true); await render(); }, notify);
  if (route === '/home' || route === '/tasks' || route === '/progress' || route === '/profile') {
    root.innerHTML = '<section class="boot-screen"><span class="loader"></span><p>Loading today’s plan…</p></section>';
    try {
      const home = await ensureHome(token); if (!home || token !== renderToken) return;
      if (route === '/home') renderHome(root, home, { resume: () => notify('Chat screen arrives in Stage 5.'), openPartner: () => notify('Chat screen arrives in Stage 5.') });
      if (route === '/tasks') renderTasks(root, home);
      if (route === '/progress') renderProgress(root, home);
      if (route === '/profile') renderProfile(root, home, state.user, { navigate, notify, logout: async () => { try { await logout(); store.set({ session: null, user: null, home: null }); navigate('/', true); await render(); } catch (error) { notify(error.message || 'Could not log out.'); } } });
    }
    catch (error) { root.innerHTML = `<section class="error-screen"><h2>We could not load today’s plan</h2><p>${String(error.message || 'Please try again.')}</p><button class="button button-primary" data-retry>Try Again</button></section>`; root.querySelector('[data-retry]')?.addEventListener('click', render); }
    return;
  }
  showPlaceholder(route);
}

async function bootstrap() {
  try { const session = await getSession(); store.set({ session, user: session?.user || null, loading: false }); }
  catch (error) { store.set({ loading: false }); notify(error.message || 'Account service is unavailable.'); }
  watchAuth((session) => { const before = store.get().session?.user?.id; store.set({ session, user: session?.user || null }); if (before !== session?.user?.id) render(); });
  onRouteChange(render);
  await render();
}

window.addEventListener('DOMContentLoaded', bootstrap, { once: true });
