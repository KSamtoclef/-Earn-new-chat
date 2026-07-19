const safe = (value = '') => String(value).replace(/[&<>'"]/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c]));
const levels = [
  ['New Member','Daily goals and starter partners'],
  ['Active Chatter','More partner choices'],
  ['Top Conversationalist','Higher-level challenges'],
  ['Verified Member','Verified badge and emerald theme'],
  ['Elite Member','Exclusive topics and elite badge']
];

export function renderProgress(root, home) {
  const current = Number(home.progression?.level_number || 1);
  const points = Number(home.progression?.points || 0);
  const next = Number(home.progression?.next_points || points);
  const levelProgress = next > points ? Math.min(100, Math.round(points / next * 100)) : 100;
  root.innerHTML = `<section class="page">
    <h1 class="page-title">Your Progress</h1><p class="page-subtitle">Meaningful conversations, completed goals and daily returns move you forward.</p>
    <article class="level-hero"><div class="level-number">${current}</div><span class="eyebrow">Current level</span><h2>${safe(home.progression?.level || 'New Member')}</h2><p>${next > points ? `${next - points} points until your next level` : 'Highest level reached'}</p><div class="progress-row"><span>${points} points</span><span>${next || points}</span></div><div class="progress-track"><i style="width:${levelProgress}%"></i></div></article>
    <article class="streak-card"><div><strong>🔥 ${home.streak?.current_streak || 0} days</strong><span>Longest streak: ${home.streak?.longest_streak || 0} days</span></div><div class="status">Active</div></article>
    <div class="section-heading"><h2>Level journey</h2></div><div class="milestone-list">${levels.map((level,index) => `<article class="milestone ${index + 1 <= current ? 'reached' : ''}"><div class="milestone-badge">${index + 1}</div><div><h3>${safe(level[0])}</h3><p>${safe(level[1])}</p></div><span>${index + 1 <= current ? '✓' : '🔒'}</span></article>`).join('')}</div>
  </section>`;
}
