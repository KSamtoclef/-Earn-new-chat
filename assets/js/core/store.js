const state = { session: null, user: null, home: null, route: '/', loading: true };
const listeners = new Set();

export const store = {
  get: () => ({ ...state }),
  set(patch) { Object.assign(state, patch); listeners.forEach((listener) => listener({ ...state })); },
  subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); }
};
