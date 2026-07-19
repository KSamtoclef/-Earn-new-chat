import { login, register } from '../services/auth.js';
import { countries, detectCountry, saveCountry } from '../core/countries.js';

function escape(value = '') { return String(value).replace(/[&<>'"]/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c])); }

export function renderAuth(root, mode, onSuccess, notify) {
  const isRegister = mode === 'register';
  root.innerHTML = `<section class="page auth-page"><div class="auth-card">
    <div class="auth-symbol">${isRegister ? '🎉' : '👋'}</div>
    <h1>${isRegister ? 'Create your account' : 'Welcome back'}</h1>
    <p class="auth-intro">${isRegister ? 'Start your five-day Earn Chat journey.' : 'Continue your conversations, streak and daily goals.'}</p>
    <form class="form" data-auth-form novalidate>
      ${isRegister ? '<div class="field"><label for="full-name">Full name</label><input id="full-name" name="fullName" autocomplete="name" minlength="2" maxlength="80" required></div>' : ''}
      ${isRegister ? `<div class="field"><label for="country">Country</label><select id="country" name="country" autocomplete="country" required><option value="">Select your country</option>${countries.map((country) => `<option value="${country.code}">${escape(country.name)}</option>`).join('')}</select><small class="field-hint">Suggested automatically when available. You can always change it.</small></div>` : ''}
      <div class="field"><label for="email">Email address</label><input id="email" name="email" type="email" inputmode="email" autocomplete="email" required></div>
      <div class="field"><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="${isRegister ? 'new-password' : 'current-password'}" minlength="6" required></div>
      <div class="form-error" data-error hidden></div>
      <button class="button button-primary" type="submit">${isRegister ? 'Create Account →' : 'Log In & Continue →'}</button>
    </form>
    <p class="auth-switch">${isRegister ? 'Already have an account? <a href="#/login">Log in</a>' : 'New to Earn Chat? <a href="#/register">Create account</a>'}</p>
  </div></section>`;
  const form = root.querySelector('[data-auth-form]');
  const errorBox = root.querySelector('[data-error]');
  const countrySelect = root.querySelector('#country');
  if (countrySelect) detectCountry().then((code) => { if (code && countrySelect.querySelector(`option[value="${code}"]`)) countrySelect.value = code; });
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    errorBox.hidden = true;
    if (!form.reportValidity()) return;
    const button = form.querySelector('button');
    button.disabled = true;
    try {
      const fields = Object.fromEntries(new FormData(form));
      if (isRegister) saveCountry(fields.country);
      const result = isRegister ? await register(fields) : await login(fields);
      if (isRegister && !result.session) notify('Account created. Check your email if confirmation is required.');
      await onSuccess(result.session);
    } catch (error) {
      errorBox.textContent = escape(error.message || 'The request could not be completed.');
      errorBox.hidden = false;
    } finally { button.disabled = false; }
  });
}
