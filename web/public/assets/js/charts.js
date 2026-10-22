// Chart helpers on top of the vendored Chart.js, applying the dataviz specs:
// thin marks (bars ≤ 24px, 4px rounded data-ends, 2px lines, ≥8px markers with
// a surface ring), hairline solid gridlines, categorical slots in fixed order,
// tooltips on hover, a legend only when there are two or more series, and a
// table-view twin under every chart.
(function () {
  'use strict';

  function cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  function palette() {
    return [cssVar('--series-1'), cssVar('--series-2'), cssVar('--series-3'), cssVar('--series-4')];
  }

  function chrome() {
    return {
      surface: cssVar('--surface'),
      grid: cssVar('--grid'),
      baseline: cssVar('--baseline'),
      muted: cssVar('--muted'),
      text: cssVar('--text'),
      text2: cssVar('--text-2'),
    };
  }

  function baseDefaults() {
    const c = chrome();
    Chart.defaults.font.family = 'system-ui, -apple-system, "Segoe UI", sans-serif';
    Chart.defaults.font.size = 12;
    Chart.defaults.color = c.muted;
    Chart.defaults.plugins.tooltip.padding = 8;
    Chart.defaults.plugins.legend.labels.boxWidth = 12;
    Chart.defaults.plugins.legend.labels.boxHeight = 12;
    Chart.defaults.plugins.legend.labels.color = c.text2;
  }

  /** Hour-denominated axes (yTitle 'hours' or opts.hours) render their tick
   * labels and tooltips as "Xh Ymin" instead of a bare decimal. */
  function hourAxis(o) {
    return o.yTitle === 'hours' || !!o.hours;
  }

  function tooltipConfig(o) {
    const hourY = hourAxis(o);
    return {
      mode: 'index',
      intersect: false,
      ...(hourY ? {
        callbacks: {
          label: (ctx) => ' ' + (ctx.dataset.label || '') + ': ' +
            window.ui.fmtH(o.horizontal ? ctx.parsed.x : ctx.parsed.y),
        },
      } : {}),
    };
  }

  function scales(opts) {
    const c = chrome();
    const o = opts || {};
    return {
      x: {
        stacked: !!o.stacked,
        grid: { display: false },
        border: { color: c.baseline },
        ticks: { display: !o.hideXTicks, color: c.muted, maxRotation: 0, autoSkip: true },
        title: o.xTitle ? { display: true, text: o.xTitle, color: c.muted } : undefined,
      },
      y: {
        stacked: !!o.stacked,
        beginAtZero: true,
        min: o.min,
        max: o.max,
        grid: { color: c.grid, lineWidth: 1 },
        border: { display: false },
        ticks: {
          color: c.muted,
          precision: o.integer ? 0 : undefined,
          stepSize: o.stepSize,
          callback: hourAxis(o) ? (v) => window.ui.fmtH(v) : undefined,
        },
        title: o.yTitle ? { display: true, text: o.yTitle, color: c.muted } : undefined,
      },
    };
  }

  function legendFor(datasets) {
    return { display: datasets.length >= 2, position: 'bottom' };
  }

  /**
   * datasets: [{label, data, slot}] - slot indexes the fixed categorical
   * order; the color follows the series, never its position on screen.
   */
  function barConfig(labels, datasets, opts) {
    const colors = palette();
    const c = chrome();
    const o = opts || {};
    const horizontal = !!o.horizontal;
    return {
      type: 'bar',
      data: {
        labels: labels,
        datasets: datasets.map((ds) => ({
          label: ds.label,
          data: ds.data,
          backgroundColor: colors[ds.slot ?? 0],
          maxBarThickness: 24,
          borderRadius: o.stacked ? 2 : (horizontal
            ? { topRight: 4, bottomRight: 4 }
            : { topLeft: 4, topRight: 4 }),
          borderSkipped: o.stacked ? false : 'start',
          borderColor: c.surface,
          borderWidth: o.stacked ? 2 : 0,
        })),
      },
      options: {
        indexAxis: horizontal ? 'y' : 'x',
        responsive: true,
        maintainAspectRatio: false,
        scales: horizontal
          ? (() => { const s = scales(o); return { x: Object.assign(s.y, { position: 'bottom' }), y: Object.assign(s.x, {}) }; })()
          : scales(o),
        plugins: {
          legend: legendFor(datasets),
          tooltip: tooltipConfig(o),
        },
      },
    };
  }

  function lineConfig(labels, datasets, opts) {
    const colors = palette();
    const c = chrome();
    const o = opts || {};
    return {
      type: 'line',
      data: {
        labels: labels,
        datasets: datasets.map((ds) => ({
          label: ds.label,
          data: ds.data,
          borderColor: colors[ds.slot ?? 0],
          backgroundColor: o.area ? colors[ds.slot ?? 0] + '1A' : colors[ds.slot ?? 0],
          fill: !!o.area,
          borderWidth: 2,
          tension: 0.3,
          pointRadius: 4,
          pointBackgroundColor: colors[ds.slot ?? 0],
          pointBorderColor: c.surface,
          pointBorderWidth: 2,
          pointHitRadius: 12,
        })),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        scales: scales(o),
        plugins: {
          legend: legendFor(datasets),
          tooltip: tooltipConfig(o),
        },
      },
    };
  }

  /** slices: [{label, value, slot}] - part-to-whole only, ≤ 6 slices. */
  function doughnutConfig(slices) {
    const colors = palette();
    const c = chrome();
    return {
      type: 'doughnut',
      data: {
        labels: slices.map((s) => s.label),
        datasets: [{
          data: slices.map((s) => s.value),
          backgroundColor: slices.map((s) => colors[s.slot ?? 0]),
          borderColor: c.surface,
          borderWidth: 2,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '62%',
        plugins: { legend: { display: true, position: 'bottom' } },
      },
    };
  }

  /**
   * Renders a chart card: title, canvas, and the table-view twin (the
   * accessibility fallback - values are always reachable without hover).
   * table: { headers: [], rows: [[]] }
   *
   * spec.scrollX + spec.minWidthPerCategory: instead of squeezing every
   * category into the card's width, give the canvas a fixed pixel width
   * (categories * minWidthPerCategory, never less than the card itself) and
   * let the wrap scroll horizontally - so charts stay readable as the
   * category count grows instead of endlessly shrinking each bar.
   */
  function card(parent, spec) {
    const e = window.ui.el;
    const wrap = e('div', { class: 'chart-wrap' + (spec.tall ? ' tall' : '') + (spec.scrollX ? ' scroll-x' : '') });
    const canvas = e('canvas');
    const scrollInner = spec.scrollX ? e('div', { class: 'chart-scroll-inner' }, [canvas]) : null;
    wrap.appendChild(scrollInner || canvas);

    const cardEl = e('div', { class: 'card chart-card' }, [
      e('h3', { text: spec.title }),
      spec.sub ? e('p', { class: 'sub', text: spec.sub }) : null,
      wrap,
      spec.table
        ? e('details', { class: 'table-view' }, [
            e('summary', { text: 'View data as table' }),
            window.ui.dataTable(spec.table.headers, spec.table.rows, spec.table.formatters),
          ])
        : null,
    ]);
    parent.appendChild(cardEl);

    if (scrollInner) {
      const categories = (spec.config.data.labels || []).length;
      const needed = categories * (spec.minWidthPerCategory || 80);
      scrollInner.style.width = Math.max(needed, wrap.clientWidth) + 'px';
    }

    baseDefaults();
    new Chart(canvas.getContext('2d'), spec.config);
    return cardEl;
  }

  window.charts = { palette, chrome, barConfig, lineConfig, doughnutConfig, card };
})();
