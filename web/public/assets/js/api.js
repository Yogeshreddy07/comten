"use strict";
// The preserved UI consumes this envelope; all business operations stay in FastAPI.
(() => {
    function token() {
        try {
            return JSON.parse(sessionStorage.getItem('session') || 'null')?.token || null;
        }
        catch {
            return null;
        }
    }
    async function request(path, options = {}) {
        const headers = { 'Content-Type': 'application/json' };
        if (options.auth !== false) {
            const value = token();
            if (value)
                headers.Authorization = `Bearer ${value}`;
        }
        let response;
        try {
            response = await fetch(window.APP_CONFIG.API_BASE_URL + path, { method: options.method || 'GET', headers, body: options.body === undefined ? undefined : JSON.stringify(options.body) });
        }
        catch {
            throw new Error('Cannot reach the backend. Is it running?');
        }
        if (response.status === 401 && options.auth !== false) {
            sessionStorage.removeItem('session');
            window.location.href = (window.ROOT || '.') + '/index.html';
            throw new Error('Session expired');
        }
        let payload = null;
        try {
            payload = await response.json();
        }
        catch { }
        if (!response.ok || !payload || payload.success === false)
            throw new Error(payload?.message || `Request failed (${response.status})`);
        return payload.data;
    }
    window.api = { get: path => request(path), post: (path, body, options) => request(path, { method: 'POST', body, ...options }), delete: path => request(path, { method: 'DELETE' }) };
})();
