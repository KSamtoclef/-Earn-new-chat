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
  verifySponsored: (opportunityId) => rpc('earn_chat_verify_sponsored', { p_opportunity_id: opportunityId }),
  payoutState: () => rpc('earn_chat_get_payout_state'),
  requestWithdrawal: ({ amountMinor, methodKey, payoutDetails, dateOfBirth }) => rpc('earn_chat_request_usd_withdrawal', {
    p_amount_minor: amountMinor, p_method_key: methodKey, p_payout_details: payoutDetails, p_date_of_birth: dateOfBirth
  }),
  beginRequiredShare: (withdrawalId) => rpc('earn_chat_begin_required_share', { p_withdrawal_id: withdrawalId }),
  completeRequiredShare: (withdrawalId) => rpc('earn_chat_complete_required_share', { p_withdrawal_id: withdrawalId }),
  uploadKycDocument: async ({ file, userId, side }) => {
    const extension = ({ 'image/jpeg':'jpg','image/png':'png','image/webp':'webp','application/pdf':'pdf' })[file.type];
    if (!extension || file.size < 1 || file.size > 10485760) throw new Error('Use a JPG, PNG, WebP or PDF file under 10 MB.');
    const id = globalThis.crypto?.randomUUID ? globalThis.crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const path = `${userId}/${id}-${side}.${extension}`;
    const { error } = await getSupabase().storage.from('earn-chat-kyc').upload(path, file, { contentType:file.type, upsert:false });
    if (error) throw error;
    return { storage_path:path, document_side:side, mime_type:file.type, file_size:file.size };
  },
  submitKyc: ({ legalName, dateOfBirth, documentType, documentNumber, documents }) => rpc('earn_chat_submit_kyc', {
    p_legal_name:legalName,p_date_of_birth:dateOfBirth,p_document_type:documentType,p_document_number:documentNumber,p_documents:documents
  })
});
