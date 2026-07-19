import { config } from '../core/config.js';

const money = new Intl.NumberFormat(config.locale, { style: 'currency', currency: config.currency, maximumFractionDigits: 0 });
const safe = (value = '') => String(value).replace(/[&<>'"]/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c]));
const percent = (progress, target) => Math.min(100, Math.round((Number(progress) / Math.max(Number(target), 1)) * 100));

export function renderHome(root, home, actions) {
  const goals = Array.isArray(home.goals) ? home.goals : [];
  const tasks = Array.isArray(home.tasks) ? home.tasks : [];
  const partners = Array.isArray(home.partners) ? home.partners : [];
  const chats = Array.isArray(home.unfinished_conversations) ? home.unfinished_conversations : [];
  const primary = goals.find((goal) => goal.role === 'primary') || goals[0];
  root.innerHTML = `<section class="page dashboard">
    <div class="welcome"><div><small>● Online — ready for today</small><h1>Welcome back, ${safe((home.profile?.name || 'Member').split(' ')[0])}</h1></div><div class="balance"><span>Balance</span><strong>${money.format(home.profile?.balance || 0)}</strong></div></div>
    <article class="return-card"><span class="eyebrow">Your next step</span><h2>${chats.length ? `${chats.length} conversation${chats.length === 1 ? '' : 's'} waiting` : 'Start today’s conversation'}</h2><p>${chats.length ? 'Continue from the exact topic where you stopped.' : 'Meet a partner matched to your current level and daily rotation.'}</p><button class="button button-primary" data-primary-action>${chats.length ? 'Continue Chat →' : 'Choose a Partner →'}</button><div class="summary-pills"><span class="pill">🔥 ${home.streak?.current_streak || 0}-day streak</span><span class="pill">⭐ ${safe(home.progression?.level || 'New Member')}</span><span class="pill">Day ${home.profile?.day || 1} of 5</span></div></article>
    <div class="section-heading"><h2>Today’s Goal</h2><a href="#/tasks">View all</a></div>
    ${primary ? `<article class="goal-card primary"><div class="card-kicker">Primary goal</div><h3>${safe(primary.title)}</h3><p>${safe(primary.description)}</p><div class="progress-row"><span>Progress</span><span>${primary.progress}/${primary.target}</span></div><div class="progress-track"><i style="width:${percent(primary.progress,primary.target)}%"></i></div></article>` : '<div class="empty-card">Today’s goal is being prepared.</div>'}
    <div class="section-heading"><h2>Available Tasks</h2><a href="#/tasks">Task centre</a></div><div class="card-list">${tasks.slice(0,3).map((task) => `<article class="task-card"><div class="task-icon">${task.type === 'sponsored' ? '🎯' : task.type === 'return' ? '↩' : '✓'}</div><div><h3>${safe(task.title)}</h3><p>${safe(task.description)}</p></div><span class="status">${safe(task.status)}</span></article>`).join('') || '<div class="empty-card">No tasks available yet.</div>'}</div>
    <div class="section-heading"><h2>Chat Partners</h2><span class="status">${partners.length} available</span></div><div class="partner-grid">${partners.map((partner) => `<article class="partner-card" tabindex="0" role="button" data-partner="${safe(partner.partner_key)}"><div class="partner-avatar">${safe(partner.avatar)}</div><h3>${safe(partner.display_name)}</h3><p>${safe(partner.conversation_mood)} · ${safe(partner.location)}</p></article>`).join('')}</div>
  </section>`;
  root.querySelector('[data-primary-action]')?.addEventListener('click', () => chats[0] ? actions.resume(chats[0]) : root.querySelector('[data-partner]')?.scrollIntoView({ behavior: 'smooth', block: 'center' }));
  root.querySelectorAll('[data-partner]').forEach((card) => {
    const open = () => actions.openPartner(card.dataset.partner);
    card.addEventListener('click', open);
    card.addEventListener('keydown', (event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); open(); } });
  });
}
