import { config } from '../core/config.js';

let client;
export function getSupabase() {
  if (client) return client;
  if (!window.supabase?.createClient) throw new Error('Secure account service could not load. Please refresh.');
  client = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  return client;
}
