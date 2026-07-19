import { store } from './core/store.js';
import { currentRoute, isPublicRoute, navigate, onRouteChange } from './core/router.js';
import { getSession, logout, watchAuth } from './services/auth.js';
import { platform } from './services/platform.js';
import { renderAuth } from './features/auth-view.js';
import { renderHome } from './features/home-view.js';
import { renderTasks } from './features/tasks-view.js';
import { renderProgress } from './features/progress-view.js';
import { renderProfile } from './features/profile-view.js';
import { renderChat, setChatBusy, showQuality } from './features/chat-view.js';

const root = document.getElementById('app');
const header = document.querySelector('[data-public-header]');
const nav = document.querySelector('[data-bottom-nav]');
const toastRegion = document.getElementById('toast-region');
let renderToken = 0;

function createClientMessageId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `earn-chat-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

function notify(message) {
  const item = document.createElement('div'); item.className = 'toast'; item.textContent = message;
  toastRegion.append(item); setTimeout(() => item.remove(), 3500);
}

function showLanding() {
  root.innerHTML = `<section class="page hero"><div class="flag-row"><span>🇺🇸</span><span>🇬🇧</span><span>🇨🇦</span><span>🇬🇭</span><span class="more">+190</span></div><div class="eyebrow">A worldwide conversation platform</div><h1>Chat With People<br><em>Across The World</em></h1><p class="hero-copy">Build meaningful conversations, complete daily goals and grow your Earn Chat progress from wherever you live.</p><div class="hero-actions"><a class="button button-primary" href="#/register">Start Chatting — Free →</a><a class="button button-secondary" href="#/login">Log In & Continue</a></div><div class="trust-row"><span>✓ Free to join</span><span>✓ Country-aware experience</span><span>✓ Server-secured progress</span></div><article class="feature-strip"><strong>Your conversations continue when you return</strong><p>Daily topics, partner memory, streak milestones and clear progression make every visit useful.</p></article></section>`;
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

async function ensureWallet(token,force=false) {
  const cached=store.get().wallet;
  if(cached&&!force)return cached;
  const wallet=await platform.wallet();
  if(token!==renderToken)return null;
  store.set({wallet});return wallet;
}

async function openChat(partnerKey) {
  root.innerHTML='<section class="boot-screen"><span class="loader"></span><p>Opening conversation…</p></section>';
  try { const chat=await platform.openConversation(partnerKey);store.set({activeChat:chat});navigate(`/chat/${encodeURIComponent(partnerKey)}`);await render(); }
  catch(error){notify(error.message||'Conversation could not open.');navigate('/home',true);await render();}
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
  if(route.startsWith('/chat/'))nav.hidden=true;
  if (route === '/') return showLanding();
  if (route === '/login' || route === '/register') return renderAuth(root, route.slice(1), async () => { const session = await getSession(); store.set({ session, user: session?.user || null }); navigate('/home', true); await render(); }, notify);
  if (route === '/home' || route === '/tasks' || route === '/progress' || route === '/profile') {
    root.innerHTML = '<section class="boot-screen"><span class="loader"></span><p>Loading today’s plan…</p></section>';
    try {
      const [home,wallet]=await Promise.all([ensureHome(token),ensureWallet(token)]); if (!home || !wallet || token !== renderToken) return;
      if (route === '/home') renderHome(root, home, wallet, { openPartner: openChat });
      if (route === '/tasks') renderTasks(root, home);
      if (route === '/progress') renderProgress(root, home);
      if (route === '/profile') renderProfile(root, home, wallet, state.user, { navigate, notify, logout: async () => { try { await logout(); store.set({ session: null, user: null, home: null, wallet: null, activeChat:null }); navigate('/', true); await render(); } catch (error) { notify(error.message || 'Could not log out.'); } } });
    }
    catch (error) { root.innerHTML = `<section class="error-screen"><h2>We could not load today’s plan</h2><p>${String(error.message || 'Please try again.')}</p><button class="button button-primary" data-retry>Try Again</button></section>`; root.querySelector('[data-retry]')?.addEventListener('click', render); }
    return;
  }
  if(route.startsWith('/chat/')){
    try{
      const partnerKey=decodeURIComponent(route.slice(6));
      let chat=store.get().activeChat;
      if(!chat||chat.partner?.partner_key!==partnerKey){root.innerHTML='<section class="boot-screen"><span class="loader"></span><p>Restoring conversation…</p></section>';chat=await platform.openConversation(partnerKey);store.set({activeChat:chat});}
      let wallet=await ensureWallet(token);if(token!==renderToken)return;
      const draw=()=>renderChat(root,store.get().activeChat,store.get().wallet,{
        back:()=>navigate('/home'),tasks:()=>navigate('/tasks'),
        send:async({content,selectedIntent})=>{
          if(store.get().activeChat?.sending)return;
          const current=store.get().activeChat;
          current.messages=[...(current.messages||[]),{sender:'user',content}];current.sending=true;store.set({activeChat:current});draw();setChatBusy(root,true);
          const before=Number(store.get().wallet?.balances?.USD||0);
          try{
            const result=await platform.sendMessage({threadId:current.thread_id,content,clientMessageId:createClientMessageId(),selectedIntent});
            const freshWallet=await platform.wallet();const credited=Number(freshWallet?.balances?.USD||0)-before;
            const optimisticMessage=current.messages[current.messages.length-1];
            if (optimisticMessage?.sender === 'user') optimisticMessage.quality_label=result.quality_label;
            current.messages.push({sender:'partner',content:result.partner_message?.content});current.suggestions=result.suggestions||[];current.conversation_completed=Boolean(result.conversation_completed);current.status=result.conversation_completed?'completed':'active';current.meaningful_message_count=Number(current.meaningful_message_count||0)+(result.quality_label==='meaningful'?1:0);current.sending=false;
            store.set({activeChat:current,wallet:freshWallet,home:null});draw();showQuality(root,result,credited);
          }catch(error){current.sending=false;current.messages=current.messages.slice(0,-1);store.set({activeChat:current});draw();notify(error.message||'Message could not be sent.');}
        }
      });draw();
    }catch(error){notify(error.message||'Conversation could not be restored.');navigate('/home',true);await render();}
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
