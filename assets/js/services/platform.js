import { getSupabase } from './supabase.js';

async function rpc(name, params = {}) {
  const { data, error } = await getSupabase().rpc(name, params);
  if (error) throw error;
  return data;
}

export const platform = Object.freeze({
  home: () => rpc('earn_chat_get_home_state'),
  openConversation: (partnerKey) => rpc('earn_chat_open_conversation', { p_partner_key: partnerKey }),
  sendMessage: ({ threadId, content, clientMessageId, selectedIntent = null }) => rpc('earn_chat_send_message', {
    p_thread_id: threadId, p_content: content, p_client_message_id: clientMessageId, p_selected_intent: selectedIntent
  })
});
