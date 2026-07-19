import { getSupabase } from './supabase.js';

async function rpc(name, params = {}) {
  const { data, error } = await getSupabase().rpc(name, params);
  if (error) throw error;
  return data;
}

export const platform = Object.freeze({
  home: () => rpc('earn_chat_get_home_state'),
  wallet: () => rpc('earn_chat_get_wallet_state'),
  setCountry: (countryCode, preferredCurrency = 'USD') => rpc('earn_chat_set_country', { p_country_code: countryCode, p_preferred_currency: preferredCurrency }),
  openConversation: (partnerKey) => rpc('earn_chat_open_conversation', { p_partner_key: partnerKey }),
  sendMessage: ({ threadId, content, clientMessageId, selectedIntent = null }) => rpc('earn_chat_send_message', {
    p_thread_id: threadId, p_content: content, p_client_message_id: clientMessageId, p_selected_intent: selectedIntent
  }),
  inlineSponsored: (threadId) => rpc('earn_chat_get_inline_sponsored', { p_thread_id: threadId }),
  sponsoredImpression: (opportunityId) => rpc('earn_chat_record_sponsored_impression', { p_opportunity_id: opportunityId }),
  beginSponsored: (opportunityId) => rpc('earn_chat_begin_sponsored', { p_opportunity_id: opportunityId }),
  sponsoredReturn: (opportunityId) => rpc('earn_chat_record_sponsored_return', { p_opportunity_id: opportunityId }),
  verifySponsored: (opportunityId) => rpc('earn_chat_verify_sponsored', { p_opportunity_id: opportunityId })
});
