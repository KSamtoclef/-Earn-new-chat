import { config } from '../core/config.js';
const money = new Intl.NumberFormat(config.locale, { style: 'currency', currency: config.currency, maximumFractionDigits: 0 });
const safe = (value = '') => String(value).replace(/[&<>'"]/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c]));

export function renderProfile(root, home, user, actions) {
  const name = home.profile?.name || 'Earn Chat Member';
  const initials = name.split(/\s+/).filter(Boolean).slice(0,2).map((part) => part[0]).join('').toUpperCase() || 'EC';
  root.innerHTML = `<section class="page">
    <h1 class="page-title">My Profile</h1><p class="page-subtitle">Your account, five-day journey and secure session.</p>
    <article class="profile-head"><div class="profile-avatar">${safe(initials)}</div><h2>${safe(name)}</h2><p>${safe(user?.email || '')}</p><div class="profile-stats"><div class="profile-stat"><strong>${money.format(home.profile?.balance || 0)}</strong><span>Balance</span></div><div class="profile-stat"><strong>Day ${home.profile?.day || 1}</strong><span>Journey</span></div><div class="profile-stat"><strong>Lv. ${home.progression?.level_number || 1}</strong><span>Level</span></div></div></article>
    <div class="section-heading"><h2>Account</h2></div><div class="menu-list">
      <button class="menu-item" data-route="/progress"><i>⭐</i><span><strong>Progress and levels</strong><small>View streaks and upcoming unlocks</small></span><b>›</b></button>
      <button class="menu-item" data-route="/tasks"><i>✓</i><span><strong>Daily tasks</strong><small>Review goals and task progress</small></span><b>›</b></button>
      <button class="menu-item" data-notice="Withdrawal and KYC arrive in Stage 6."><i>🪪</i><span><strong>KYC and withdrawal</strong><small>Secure verification and payout journey</small></span><b>›</b></button>
      <button class="menu-item" data-notice="Support details will be added before production cutover."><i>?</i><span><strong>Help and support</strong><small>Account and platform assistance</small></span><b>›</b></button>
      <button class="menu-item danger" data-logout><i>↪</i><span><strong>Log out</strong><small>End this device session</small></span><b>›</b></button>
    </div><p class="legal-note">Earn Chat uses server-authoritative balances and progress. Never share your password or verification code with anyone.</p>
  </section>`;
  root.querySelectorAll('[data-route]').forEach((button) => button.addEventListener('click', () => actions.navigate(button.dataset.route)));
  root.querySelectorAll('[data-notice]').forEach((button) => button.addEventListener('click', () => actions.notify(button.dataset.notice)));
  root.querySelector('[data-logout]')?.addEventListener('click', actions.logout);
}
