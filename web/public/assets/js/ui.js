// Shared page shell (topbar, theme handling) and small DOM/format helpers.
// All dynamic text is inserted via textContent - never innerHTML - because
// names and labels come from API data.
(function () {
  'use strict';

  const NAV = [
    { id: 'dashboard', label: 'Dashboard', href: 'dashboard.html', root: true },
    { id: 'attendance', label: 'Attendance', href: 'reports/attendance.html' },
    { id: 'working-hours', label: 'Working Hours', href: 'reports/working-hours.html' },
    { id: 'project-utilization', label: 'Project Time', href: 'reports/project-utilization.html' },
    { id: 'project-billing', label: 'Project Billing', href: 'reports/project-billing.html' },
    { id: 'clients', label: 'Clients', href: 'reports/clients.html' },
    { id: 'billing-status', label: 'Billing Status', href: 'reports/billing-status.html' },
  ];

  // --- theme ---

  function applyTheme() {
    const saved = localStorage.getItem('theme');
    if (saved === 'light' || saved === 'dark') {
      document.documentElement.setAttribute('data-theme', saved);
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
  }

  function isDark() {
    const saved = localStorage.getItem('theme');
    if (saved) return saved === 'dark';
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function toggleTheme() {
    localStorage.setItem('theme', isDark() ? 'light' : 'dark');
    // Selection state lives in the URL, so a reload re-renders every chart
    // against the new theme without losing where the user was.
    window.location.reload();
  }

  // --- DOM helpers ---

  /** el('div', {class:'card'}, [child, 'text']) - children as text nodes by default. */
  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    if (attrs) {
      for (const key of Object.keys(attrs)) {
        if (key === 'class') node.className = attrs[key];
        else if (key === 'text') node.textContent = attrs[key];
        else if (key.startsWith('on')) node.addEventListener(key.slice(2), attrs[key]);
        else node.setAttribute(key, attrs[key]);
      }
    }
    if (children) {
      for (const child of [].concat(children)) {
        if (child == null) continue;
        node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
      }
    }
    return node;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
    return node;
  }

  function qs(name) {
    return new URLSearchParams(window.location.search).get(name);
  }

  function goto(params) {
    const search = new URLSearchParams(window.location.search);
    for (const key of Object.keys(params)) {
      if (params[key] == null || params[key] === '') search.delete(key);
      else search.set(key, params[key]);
    }
    window.location.search = search.toString();
  }

  // --- formatting ---

  function fmtH(hours) {
    if (hours == null) return '—';
    var totalMinutes = Math.round(hours * 60);
    var h = Math.floor(totalMinutes / 60);
    var m = totalMinutes % 60;
    if (h === 0 && m === 0) return '0min';
    if (h === 0) return m + 'min';
    if (m === 0) return h + 'h';
    return h + 'h ' + m + 'min';
  }

  function fmtPct(value) {
    if (value == null) return '—';
    return (Math.round(value * 10) / 10) + '%';
  }

  function fmtTime(isoDateTime) {
    if (!isoDateTime) return '—';
    const d = new Date(isoDateTime);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function fmtDate(isoDate) {
    if (!isoDate) return '—';
    return new Date(isoDate + (isoDate.length === 10 ? 'T00:00:00' : '')).toLocaleDateString([], {
      day: '2-digit', month: 'short',
    });
  }

  function statusLabel(status) {
    const labels = {
      NOT_STARTED: 'Not Started',
      WIP: 'Work in Progress',
      READY: 'Ready',
      BILLED: 'Billed',
      PARTLY_PAID: 'Partly Paid',
      PAID: 'Paid',
      NOT_BILLED: 'Not Billed',
      IN_PROGRESS: 'In Progress',
      ON_HOLD: 'On Hold',
      COMPLETED: 'Completed',
      CANCELLED: 'Cancelled',
      INACTIVE: 'Inactive',
      UNASSIGNED: 'Unassigned',
      NOT_CHECKED_OUT: 'Not checked out',
    };
    return labels[status] || status || '—';
  }

  function statusBadge(status) {
    const tone = {
      NOT_STARTED: '', WIP: 'info', READY: 'warning',
      BILLED: 'good', PARTLY_PAID: 'serious', PAID: 'good',
      NOT_BILLED: 'warning', NOT_CHECKED_OUT: 'critical',
    }[status] || '';
    return el('span', { class: ('badge ' + tone).trim() }, [
      el('span', { class: 'dot' }),
      statusLabel(status),
    ]);
  }

  // --- widgets ---

  function statTile(label, value, hint) {
    return el('div', { class: 'stat' }, [
      el('div', { class: 'label', text: label }),
      el('div', { class: 'value', text: value }),
      hint ? el('div', { class: 'hint', text: hint }) : null,
    ]);
  }

  function meterTile(label, pct, hint) {
    const clamped = Math.max(0, Math.min(100, pct || 0));
    const tile = statTile(label, fmtPct(pct), hint);
    const meter = el('div', { class: 'meter' }, [el('span')]);
    meter.firstChild.style.width = clamped + '%';
    tile.appendChild(meter);
    return tile;
  }

  /**
   * Labeled <select> for in-page switching (e.g. jump between projects
   * without going back to the list). options: [{value, label}].
   */
  function selectFilter(labelText, options, currentValue, onChange) {
    const select = el('select', { onchange: (ev) => onChange(ev.target.value) },
      options.map((o) => {
        const opt = el('option', { value: String(o.value), text: o.label });
        if (String(o.value) === String(currentValue)) opt.setAttribute('selected', '');
        return opt;
      }));
    return el('label', null, [labelText, select]);
  }

  /**
   * "Download Excel" button for a report page. getSheets is called lazily on
   * click and must return the xlsxExport sheet specs for the current view -
   * either directly, or as a Promise (e.g. when it needs to fetch extra data
   * first), since it's always awaited before handing the result to xlsxExport.
   */
  function exportButton(filename, getSheets) {
    return el('button', {
      class: 'export-btn',
      title: 'Download this report as an Excel (.xlsx) file',
      onclick: async () => {
        try {
          const sheets = await getSheets();
          window.xlsxExport.download(filename, sheets);
        } catch (e) {
          alert('Excel export failed: ' + e.message);
        }
      },
      text: '⬇ Excel',
    });
  }

  /**
   * Data table used both standalone and as every chart's table-view twin.
   * `formatters` is an optional object mapping column index → function(value)
   * → string, so hour columns can render as "1h 30min" instead of a bare
   * decimal number.
   */
  function dataTable(headers, rows, formatters) {
    const thead = el('thead', null, [el('tr', null, headers.map((h, i) =>
      el('th', { class: typeof rows[0] !== 'undefined' && typeof (rows[0] || [])[i] === 'number' ? 'num' : '', text: h })
    ))]);
    const tbodyRows = rows.map((row) => {
      const cells = row.map((cell, i) => {
        const fmt = formatters ? formatters[i] : null;
        const text = fmt
          ? fmt(cell)
          : typeof cell === 'number'
            ? String(Math.round(cell * 100) / 100)
            : (cell == null ? '—' : String(cell));
        return el('td', { class: typeof cell === 'number' ? 'num' : '', text });
      });
      return el('tr', null, cells);
    });
    const tbody = el('tbody', null, tbodyRows);
    return el('div', { class: 'table-scroll' }, [el('table', { class: 'data' }, [thead, tbody])]);
  }

  // --- shell ---

  function initShell(activeId) {
    applyTheme();
    const user = window.auth.requireAuth();
    if (!user) return null;

    const root = window.ROOT || '.';
    const nav = el('nav', null, NAV.map((item) => el('a', {
      href: root + '/' + item.href,
      class: item.id === activeId ? 'active' : '',
      text: item.label,
    })));
    // Small-screen collapse: the nav itself is unchanged, only its
    // visibility is toggled via the "open" class (see app.css).
    nav.addEventListener('click', (ev) => {
      if (ev.target.tagName === 'A') nav.classList.remove('open');
    });
    const navToggle = el('button', {
      class: 'ghost nav-toggle',
      type: 'button',
      'aria-label': 'Toggle navigation menu',
      'aria-expanded': 'false',
      text: '☰',
      onclick: () => {
        const open = nav.classList.toggle('open');
        navToggle.setAttribute('aria-expanded', String(open));
        navToggle.textContent = open ? '✕' : '☰';
      },
    });

    const header = el('header', { class: 'topbar' }, [
      el('a', { class: 'brand', href: root + '/dashboard.html' }, [
        el('img', { class: 'brand-logo', src: root + '/assets/images/comten-logo.png', alt: 'Comten' }),
        el('span', { text: 'Comten Reports' }),
      ]),
      el('nav', null, NAV.map((item) => el('a', {
        href: root + '/' + item.href,
        class: item.id === activeId ? 'active' : '',
        text: item.label,
      }))),
      el('div', { class: 'spacer' }),
      el('span', { class: 'who', text: user.name + ' · ' + user.role }),
      el('button', { class: 'ghost', title: 'Toggle light/dark theme', onclick: toggleTheme, text: isDark() ? '☀' : '☾' }),
      el('button', { class: 'ghost', onclick: () => window.auth.logout(), text: 'Log out' }),
    ]);
    document.body.prepend(header);
    return user;
  }

  window.ui = {
    initShell, applyTheme, isDark, el, clear, qs, goto,
    fmtH, fmtPct, fmtTime, fmtDate, statusLabel, statusBadge,
    statTile, meterTile, dataTable, selectFilter, exportButton,
  };
})();
