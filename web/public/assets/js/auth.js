// Authentication built on the existing backend flow: POST /api/auth/login
// returns a JWT which is sent as "Authorization: Bearer <token>" on every
// subsequent call. The identifier may be an employee code or an email
// address - the backend resolves either.
//
// Sessions on this reports site expire after 5 minutes of inactivity
// (independent of the JWT's own lifetime, which is shared with the mobile
// app and stays untouched): any click/keypress/scroll refreshes the window,
// and a watchdog logs the user out and returns to the login page once it
// lapses.
(function () {
  'use strict';

  var SESSION_TTL_MS = 5 * 60 * 1000;
  var ACTIVITY_KEY = 'sessionLastActivity';
  // Only these roles may use the reports website - everyone else gets a
  // clear rejection instead of a dashboard that has nothing they can see.
  var ALLOWED_ROLES = ['PROJECT_CONTROLLER', 'CAPTAIN'];
  var ACCESS_DENIED_MESSAGE = 'You do not have permission to access the Reports website.';

  function session() {
    try {
      return JSON.parse(sessionStorage.getItem('session') || 'null');
    } catch (e) {
      return null;
    }
  }

  function touchActivity() {
    localStorage.setItem(ACTIVITY_KEY, String(Date.now()));
  }

  function isExpired() {
    var last = parseInt(localStorage.getItem(ACTIVITY_KEY) || '0', 10);
    return !last || (Date.now() - last) > SESSION_TTL_MS;
  }

  function clearSession() {
    sessionStorage.removeItem('session');
    localStorage.removeItem(ACTIVITY_KEY);
  }

  function isAllowedRole(role) {
    return ALLOWED_ROLES.indexOf(role) !== -1;
  }

  async function login(identifier, password) {
    const data = await window.api.post(
      '/api/auth/login',
      { employeeCode: identifier, password: password },
      { auth: false }
    );
    if (!isAllowedRole(data.role)) {
      throw new Error(ACCESS_DENIED_MESSAGE);
    }
    sessionStorage.setItem('session', JSON.stringify({
      token: data.token,
      userId: data.userId,
      employeeCode: data.employeeCode,
      name: data.name,
      role: data.role,
    }));
    touchActivity();
    return data;
  }

  async function logout() {
    try {
      await window.api.post('/api/auth/logout', {});
    } catch (e) {
      /* best effort - the token is dropped locally regardless */
    }
    clearSession();
    window.location.href = (window.ROOT || '.') + '/index.html';
  }

  function redirectToLogin() {
    window.location.href = (window.ROOT || '.') + '/index.html';
  }

  /** Sliding-window watchdog: user activity refreshes the 5-minute clock. */
  function startExpiryWatch() {
    var refresh = function () { touchActivity(); };
    ['click', 'keydown', 'scroll', 'touchstart'].forEach(function (eventName) {
      window.addEventListener(eventName, refresh, { passive: true });
    });
    setInterval(function () {
      if (session() && isExpired()) {
        clearSession();
        redirectToLogin();
      }
    }, 15 * 1000);
  }

  /** Call at the top of every protected page. */
  function requireAuth() {
    const s = session();
    if (!s || !s.token) {
      redirectToLogin();
      return null;
    }
    if (isExpired() || !isAllowedRole(s.role)) {
      clearSession();
      redirectToLogin();
      return null;
    }
    touchActivity();
    startExpiryWatch();
    return s;
  }

  window.auth = {
    session: session, login: login, logout: logout, requireAuth: requireAuth,
    isAllowedRole: isAllowedRole,
  };
})();
