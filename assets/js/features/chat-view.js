import { config } from '../core/config.js';

const usd = new Intl.NumberFormat(config.locale,{style:'currency',currency:'USD',minimumFractionDigits:2});
const safe = (value='') => String(value).replace(/[&<>'"]/g,(c)=>({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c]));

function messageMarkup(message) {
  const side = message.sender === 'user' ? 'user' : message.sender === 'system' ? 'system' : 'partner';
  return `<div class="chat-message ${side}"><div class="chat-bubble">${safe(message.content)}</div>${message.quality_label ? `<span class="message-quality ${safe(message.quality_label)}">${safe(message.quality_label.replace('_',' '))}</span>` : ''}</div>`;
}

export function renderChat(root, chat, wallet, actions) {
  const partner = chat.partner || {};
  const messages = Array.isArray(chat.messages) ? chat.messages : [];
  const completed = chat.status === 'completed' || chat.conversation_completed;
  root.innerHTML = `<section class="chat-page">
    <header class="chat-header"><button class="chat-back" data-back aria-label="Back to dashboard">←</button><div class="chat-avatar">${safe(partner.avatar || '💬')}</div><div class="chat-person"><strong>${safe(partner.display_name || 'Chat Partner')}</strong><span><i></i>${completed ? 'Conversation complete' : `${safe(partner.conversation_mood || 'friendly')} · online`}</span></div><div class="chat-wallet"><small>Balance</small><strong>${usd.format(Number(wallet?.balances?.USD || 0)/100)}</strong></div></header>
    <div class="chat-context"><span>${safe(partner.location || 'Worldwide')}</span><b>Meaningful replies ${chat.meaningful_message_count || 0}</b></div>
    <div class="chat-messages" data-messages>${messages.map(messageMarkup).join('')}${completed ? completionMarkup() : ''}</div>
    ${completed ? '' : `<div class="suggestions" data-suggestions>${suggestionMarkup(chat.suggestions)}</div><form class="chat-composer" data-composer><textarea name="message" rows="1" maxlength="1200" placeholder="Write a meaningful reply…" aria-label="Message"></textarea><button type="submit" aria-label="Send message">➤</button></form>`}
    <div class="quality-feedback" data-feedback hidden></div>
  </section>`;
  const messageBox = root.querySelector('[data-messages]');
  messageBox.scrollTop = messageBox.scrollHeight;
  root.querySelector('[data-back]')?.addEventListener('click',actions.back);
  root.querySelectorAll('[data-intent]').forEach((button)=>button.addEventListener('click',()=>actions.send({content:button.textContent.trim(),selectedIntent:button.dataset.intent})));
  root.querySelector('[data-composer]')?.addEventListener('submit',(event)=>{event.preventDefault();const field=event.currentTarget.elements.message;const content=field.value.trim();if(!content)return;field.value='';actions.send({content,selectedIntent:null});});
  root.querySelector('[data-new-chat]')?.addEventListener('click',actions.back);
  root.querySelector('[data-tasks]')?.addEventListener('click',actions.tasks);
}

function suggestionMarkup(suggestions) {
  return (Array.isArray(suggestions) ? suggestions : []).map((item)=>`<button type="button" data-intent="${safe(item.intent)}">${safe(item.label)}</button>`).join('');
}

function completionMarkup() {
  return `<article class="conversation-complete"><div>✓</div><h2>Conversation completed</h2><p>You reached a natural ending. Your meaningful replies and progression were recorded by the server.</p><button class="button button-primary" data-new-chat>Choose Another Partner</button><button class="button button-secondary" data-tasks>View Today’s Tasks</button></article>`;
}

export function setChatBusy(root,busy) {
  root.querySelectorAll('textarea,.chat-composer button,.suggestions button').forEach((element)=>element.disabled=busy);
  if(busy){const box=root.querySelector('[data-messages]');box.insertAdjacentHTML('beforeend','<div class="chat-message partner" data-typing><div class="typing"><i></i><i></i><i></i></div></div>');box.scrollTop=box.scrollHeight;}
  else root.querySelector('[data-typing]')?.remove();
}

export function showQuality(root,result,creditedMinor) {
  const feedback=root.querySelector('[data-feedback]');
  if(!feedback)return;
  const labels={meaningful:'Meaningful reply',good:'Good reply',needs_detail:'Try a more detailed reply'};
  feedback.className=`quality-feedback ${result.quality_label || ''}`;
  feedback.textContent=`${labels[result.quality_label] || 'Reply checked'}${creditedMinor>0 ? ` · +${usd.format(creditedMinor/100)}` : ''}`;
  feedback.hidden=false;setTimeout(()=>{feedback.hidden=true;},3200);
}
