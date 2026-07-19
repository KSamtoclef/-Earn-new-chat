import { getSupabase } from './supabase.js';

export async function getSession() {
  const { data, error } = await getSupabase().auth.getSession();
  if (error) throw error;
  return data.session;
}

export function watchAuth(callback) {
  const { data } = getSupabase().auth.onAuthStateChange((_event, session) => callback(session));
  return () => data.subscription.unsubscribe();
}

export async function register({ fullName, email, password }) {
  const { data, error } = await getSupabase().auth.signUp({
    email: email.trim().toLowerCase(), password,
    options: { data: { full_name: fullName.trim() } }
  });
  if (error) throw error;
  return data;
}

export async function login({ email, password }) {
  const { data, error } = await getSupabase().auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
  if (error) throw error;
  return data;
}

export async function logout() { const { error } = await getSupabase().auth.signOut(); if (error) throw error; }
