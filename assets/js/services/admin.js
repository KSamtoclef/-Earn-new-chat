import { getSupabase } from './supabase.js';

async function rpc(name, params = {}) {
  const { data, error } = await getSupabase().rpc(name, params);
  if (error) throw error;
  return data;
}

export const adminApi = Object.freeze({
  isAdmin: () => rpc('is_current_user_admin'),
  overview: () => rpc('earn_chat_admin_overview'),
  page: (section, page = 1, pageSize = 25, status = null) => rpc('earn_chat_admin_page', {
    p_section: section, p_page: page, p_page_size: pageSize, p_status: status || null
  }),
  reviewKyc: (caseId, action, note) => rpc('earn_chat_admin_review_kyc', {
    p_case_id: caseId, p_action: action, p_note: note || null
  }),
  reviewWithdrawal: (withdrawalId, action, note, paymentReference) => rpc('earn_chat_admin_review_withdrawal', {
    p_withdrawal_id: withdrawalId, p_action: action, p_note: note || null,
    p_payment_reference: paymentReference || null
  }),
  saveOffer: offer => rpc('earn_chat_admin_save_offer', {
    p_id: offer.id || null, p_offer_key: offer.offerKey, p_title: offer.title,
    p_description: offer.description, p_destination_url: offer.destinationUrl,
    p_placement: offer.placement, p_minimum_replies: offer.minimumReplies,
    p_minimum_seconds: offer.minimumSeconds, p_reward_minor: offer.rewardMinor,
    p_active: offer.active
  })
});
