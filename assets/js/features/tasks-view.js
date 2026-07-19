const safe = (value = '') => String(value).replace(/[&<>'"]/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c]));
const pct = (value, total) => Math.min(100, Math.round(Number(value) / Math.max(Number(total), 1) * 100));

function rewardLabel(reward = {}) {
  if (reward.progress_points) return `+${reward.progress_points} progression points`;
  if (reward.existing_reward_type) return 'Existing server-configured daily reward';
  if (reward.offer_defined) return 'Reward is defined by the eligible offer';
  if (reward.unlock_progress) return 'Unlock progress';
  return 'Progress reward';
}

export function renderTasks(root, home) {
  const goals = Array.isArray(home.goals) ? home.goals : [];
  const tasks = Array.isArray(home.tasks) ? home.tasks : [];
  const completed = tasks.filter((task) => task.status === 'completed').length;
  root.innerHTML = `<section class="page">
    <h1 class="page-title">Daily Tasks</h1><p class="page-subtitle">One primary goal and a small number of useful optional activities.</p>
    <div class="task-centre-summary"><article class="metric-card"><strong>${completed}/${tasks.length}</strong><span>Tasks completed today</span></article><article class="metric-card"><strong>${home.streak?.current_streak || 0}</strong><span>Day streak</span></article></div>
    <div class="section-heading"><h2>Today’s goals</h2></div><div class="goal-stack">${goals.map((goal) => `<article class="goal-card ${goal.role === 'primary' ? 'primary' : ''}"><span class="goal-role ${goal.role === 'primary' ? 'primary' : ''}">${safe(goal.role)}</span><h3>${safe(goal.title)}</h3><p>${safe(goal.description)}</p><div class="progress-row"><span>${safe(goal.status)}</span><span>${goal.progress}/${goal.target}</span></div><div class="progress-track"><i style="width:${pct(goal.progress,goal.target)}%"></i></div></article>`).join('') || '<div class="empty-card">Today’s goals are being prepared.</div>'}</div>
    <div class="section-heading"><h2>Task centre</h2></div><div class="goal-stack">${tasks.map((task) => `<article class="task-centre-card"><header><div class="task-icon">${task.type === 'sponsored' ? '🎯' : task.type === 'profile' ? '👤' : task.type === 'return' ? '↩' : '✓'}</div><div><h3>${safe(task.title)}</h3><p>${safe(task.description)}</p></div><span class="status">${safe(task.status)}</span></header><div class="progress-row"><span>Progress</span><span>${task.progress}/${task.target}</span></div><div class="progress-track"><i style="width:${pct(task.progress,task.target)}%"></i></div><div class="task-reward">${safe(rewardLabel(task.reward))}</div></article>`).join('') || '<div class="empty-card">No tasks are available today.</div>'}</div>
  </section>`;
}
