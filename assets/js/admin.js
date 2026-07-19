import { getSupabase } from './services/supabase.js';
import { adminApi } from './services/admin.js';

const sections = [
  ['overview','Overview','⌂'],['users','Users','●'],['live_users','Live Users','◉'],
  ['offers','Offers','◆'],['reward_slots','Reward Slots','◇'],['withdrawals','Withdrawals','$'],
  ['sharing','Sharing','↗'],['kyc','KYC','✓'],['conversations','Conversations','💬'],
  ['performance','Performance','▥'],['errors','Errors','!'],['audit','Audit Log','≡'],['settings','Settings','⚙']
];
const state = { section: 'overview', page: 1, pageSize: 25, status: '', loading: false };
const app = document.querySelector('#admin-app');
const tabs = document.querySelector('#admin-tabs');
const title = document.querySelector('#page-title');
const toast = document.querySelector('#admin-toast');

const esc = value => String(value ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const money = minor => new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(Number(minor || 0) / 100);
const date = value => value ? new Intl.DateTimeFormat('en',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : '—';
const label = value => String(value || '—').replaceAll('_',' ');
function notify(message, bad = false) { toast.textContent = message; toast.className = `admin-toast${bad ? ' bad' : ''}`; toast.hidden = false; clearTimeout(notify.timer); notify.timer = setTimeout(() => toast.hidden = true, 3500); }
function loading(message = 'Loading secure data…') { app.innerHTML = `<div class="admin-loading"><i></i><span>${esc(message)}</span></div>`; }
function empty() { return '<div class="admin-empty"><b>No records found</b><span>Try another status or refresh this section.</span></div>'; }
function status(value) { return `<span class="status status-${esc(value)}">${esc(label(value))}</span>`; }

function renderTabs() {
  tabs.innerHTML = sections.map(([key,name,icon]) => `<button type="button" data-section="${key}" class="${key===state.section?'active':''}"><i>${icon}</i><span>${name}</span></button>`).join('');
}
function controls(total) {
  const pages = Math.max(1, Math.ceil(total/state.pageSize));
  return `<div class="admin-controls"><span>${Number(total).toLocaleString()} records</span><div><button data-page="${state.page-1}" ${state.page<=1?'disabled':''}>←</button><b>${state.page} / ${pages}</b><button data-page="${state.page+1}" ${state.page>=pages?'disabled':''}>→</button></div></div>`;
}
function valueLine(name,value) { return `<div><span>${esc(name)}</span><b>${esc(value ?? '—')}</b></div>`; }
function actions(row) {
  if (state.section==='kyc' && ['pending','correction_required'].includes(row.status)) return `<div class="row-actions"><button data-action="kyc:approved" data-id="${row.id}">Approve</button><button data-action="kyc:correction_required" data-id="${row.id}">Correction</button><button class="danger" data-action="kyc:rejected" data-id="${row.id}">Reject</button></div>`;
  if (state.section==='withdrawals' && !['paid','rejected','cancelled'].includes(row.status)) return `<div class="row-actions"><button data-action="withdrawal:approved" data-id="${row.id}">Approve</button><button data-action="withdrawal:paid" data-id="${row.id}">Mark paid</button><button class="danger" data-action="withdrawal:rejected" data-id="${row.id}">Reject</button></div>`;
  if (state.section==='offers') return `<div class="row-actions"><button data-action="offer:edit" data-row="${encodeURIComponent(JSON.stringify(row))}">Edit offer</button></div>`;
  return '';
}
function rowCard(row) {
  let heading = row.full_name || row.profile_name || row.title || row.partner || row.event_name || row.action || row.setting_group || row.email || row.id || 'Record';
  let sub = row.email || row.description || row.admin_email || row.page_id || row.entity_type || '';
  const omitted = new Set(['full_name','profile_name','title','partner','event_name','action','setting_group','email','description','admin_email','page_id','payout_details','before_state','after_state','metadata','value']);
  const fields = Object.entries(row).filter(([k,v]) => !omitted.has(k) && v !== null && typeof v !== 'object').slice(0,8);
  return `<article class="data-card"><header><div><h3>${esc(heading)}</h3><p>${esc(sub)}</p></div>${row.status?status(row.status):''}</header><div class="data-grid">${fields.map(([k,v])=>valueLine(label(k),k.includes('amount')||k.includes('balance')?money(v):k.endsWith('_at')||k==='created_at'||k==='latest'?date(v):v)).join('')}</div>${actions(row)}</article>`;
}
function offerForm(row = {}) {
  return `<form id="offer-form" class="admin-form"><input type="hidden" name="id" value="${esc(row.id||'')}"><label>Offer key<input name="offerKey" required pattern="[a-z0-9][a-z0-9_-]{2,79}" value="${esc(row.offer_key||'')}"></label><label>Title<input name="title" required minlength="3" value="${esc(row.title||'')}"></label><label class="wide">Description<textarea name="description" required minlength="5">${esc(row.description||'')}</textarea></label><label class="wide">HTTPS destination<input type="url" name="destinationUrl" required pattern="https://.*" value="${esc(row.destination_url||'')}"></label><label>Placement<select name="placement"><option value="inline_chat">Inline chat</option><option value="daily_task">Daily task</option><option value="post_chat">Post chat</option></select></label><label>Reward (USD cents)<input type="number" min="0" name="rewardMinor" required value="${esc(row.reward_minor??0)}"></label><label>Meaningful replies<input type="number" min="0" name="minimumReplies" value="${esc(row.minimum_meaningful_replies??3)}"></label><label>Seconds away<input type="number" min="0" max="3600" name="minimumSeconds" value="${esc(row.minimum_seconds_away??60)}"></label><label class="check"><input type="checkbox" name="active" ${row.active!==false?'checked':''}> Active</label><div class="form-actions"><button type="button" data-close-form>Cancel</button><button class="primary" type="submit">Save offer</button></div></form>`;
}
function overview(data) {
  const cards = [['Users',data.users],['Online now',data.online_now],['Pending withdrawals',data.pending_withdrawals],['Pending KYC',data.pending_kyc],['Active conversations',data.active_conversations],['Active offers',data.active_offers],['USD wallet total',money(data.usd_wallet_total_minor)],['Errors · 24h',data.errors_24h]];
  app.innerHTML = `<div class="overview-grid">${cards.map(([k,v])=>`<article><span>${esc(k)}</span><strong>${esc(v??0)}</strong></article>`).join('')}</div><section class="admin-note"><b>Operations are live</b><p>Tabs load only when opened. Financial and moderation actions run server-side and are written to the audit log.</p><small>Updated ${date(data.generated_at)}</small></section>`;
}
async function load() {
  if (state.loading) return; state.loading=true; renderTabs(); title.textContent = sections.find(x=>x[0]===state.section)?.[1] || 'Admin'; loading();
  try {
    if (state.section==='overview') overview(await adminApi.overview());
    else {
      const data=await adminApi.page(state.section,state.page,state.pageSize,state.status||null);
      const add = state.section==='offers' ? '<button class="primary add-offer" data-new-offer>+ New offer</button>' : '';
      app.innerHTML=`<div class="section-toolbar"><label>Status filter<input id="status-filter" value="${esc(state.status)}" placeholder="All statuses"></label>${add}</div><div id="form-host"></div>${data.rows?.length?`<div class="data-list">${data.rows.map(rowCard).join('')}</div>`:empty()}${controls(data.total||0)}`;
    }
  } catch (error) { app.innerHTML=`<div class="admin-error"><b>Could not load this section</b><p>${esc(error.message)}</p><button data-retry>Try again</button></div>`; }
  finally { state.loading=false; }
}
async function handleAction(target) {
  const [kind,action]=target.dataset.action.split(':'); const id=target.dataset.id;
  if (kind==='offer') { document.querySelector('#form-host').innerHTML=offerForm(JSON.parse(decodeURIComponent(target.dataset.row))); return; }
  const note=prompt(`Optional note for ${label(action)}:`) ?? ''; if (!confirm(`Confirm ${label(action)}?`)) return;
  target.disabled=true;
  try {
    if(kind==='kyc') await adminApi.reviewKyc(id,action,note);
    else { const ref=action==='paid' ? (prompt('Payment reference (required for your records):')||'') : ''; await adminApi.reviewWithdrawal(id,action,note,ref); }
    notify(`${label(kind)} updated successfully.`); await load();
  } catch(error){ notify(error.message,true); target.disabled=false; }
}
document.addEventListener('click', async event => {
  const section=event.target.closest('[data-section]'); if(section){state.section=section.dataset.section;state.page=1;state.status='';await load();return;}
  const page=event.target.closest('[data-page]'); if(page&&!page.disabled){state.page=Number(page.dataset.page);await load();return;}
  const action=event.target.closest('[data-action]'); if(action){await handleAction(action);return;}
  if(event.target.closest('[data-new-offer]')) document.querySelector('#form-host').innerHTML=offerForm();
  if(event.target.closest('[data-close-form]')) document.querySelector('#form-host').innerHTML='';
  if(event.target.closest('[data-retry]')) load();
});
document.addEventListener('change', event=>{if(event.target.id==='status-filter'){state.status=event.target.value.trim();state.page=1;load();}});
document.addEventListener('submit',async event=>{if(event.target.id!=='offer-form')return;event.preventDefault();const f=new FormData(event.target);const button=event.target.querySelector('[type=submit]');button.disabled=true;try{await adminApi.saveOffer({id:f.get('id')||null,offerKey:f.get('offerKey'),title:f.get('title'),description:f.get('description'),destinationUrl:f.get('destinationUrl'),placement:f.get('placement'),minimumReplies:Number(f.get('minimumReplies')),minimumSeconds:Number(f.get('minimumSeconds')),rewardMinor:Number(f.get('rewardMinor')),active:f.get('active')==='on'});notify('Offer saved and audited.');await load();}catch(error){notify(error.message,true);button.disabled=false;}});
document.querySelector('#refresh-button').addEventListener('click',()=>load());
document.querySelector('#signout-button').addEventListener('click',async()=>{await getSupabase().auth.signOut();location.href='index.html#/login';});

async function boot(){
  try { const {data:{session}}=await getSupabase().auth.getSession(); if(!session){app.innerHTML='<div class="access-card"><h2>Administrator sign-in required</h2><p>Sign in through Earn Chat, then return to this page.</p><a href="index.html#/login">Go to sign in</a></div>';return;} if(!await adminApi.isAdmin()){app.innerHTML='<div class="access-card"><h2>Access denied</h2><p>This account does not have an administrator role.</p><a href="index.html">Return to Earn Chat</a></div>';return;} renderTabs();await load(); } catch(error){app.innerHTML=`<div class="admin-error"><b>Admin startup failed</b><p>${esc(error.message)}</p></div>`;}
}
boot();
