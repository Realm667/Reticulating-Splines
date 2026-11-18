/* Public activity only; no credentials, IP addresses or player rosters. */
(() => {
  const script = document.currentScript;
  const origin = new URL(script.src).origin;
  const compactFormat = new Intl.NumberFormat('en', {maximumFractionDigits: 1});
  const icons = {
    total: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-3.9M15 3.1a4 4 0 0 1 0 7.8 M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
    solo: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2 M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
    multi: 'M7 7h10a4 4 0 0 1 3.9 3.2l1 5.1a2.5 2.5 0 0 1-4.2 2.2L15 15H9l-2.7 2.5a2.5 2.5 0 0 1-4.2-2.2l1-5.1A4 4 0 0 1 7 7Zm0 3v4m-2-2h4m6-1h.01m3 2h.01',
  };

  function playerCount(icon) {
    const metric = document.createElement('button');
    metric.type = 'button';
    metric.className = 'count';
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', icons[icon]);
    svg.append(path);
    const value = document.createElement('span');
    value.setAttribute('aria-hidden', 'true');
    const tip = document.createElement('span');
    tip.className = 'count-tip';
    tip.setAttribute('aria-hidden', 'true');
    metric.append(svg, value, tip);
    metric.addEventListener('click', () => metric.focus({preventScroll: true}));
    return {metric, update(number, singular) {
      const label = number === 1 ? singular : `${singular}s`;
      const formatted = number.toLocaleString('en');
      metric.setAttribute('aria-label', `${formatted} ${label}`);
      value.textContent = formatted;
      tip.textContent = label;
    }};
  }

  function showNumber(cell, number) {
    if (!Number.isSafeInteger(number) || number < 0) {
      cell.textContent = '—';
      return;
    }
    const exact = number.toLocaleString('en');
    const unit = number >= 10_000_000 ? [1_000_000, 'M'] : number >= 10_000 ? [1_000, 'K'] : null;
    if (!unit) {
      cell.textContent = exact;
      return;
    }
    cell.title = exact;
    const abbreviated = document.createElement('span');
    abbreviated.setAttribute('aria-hidden', 'true');
    abbreviated.textContent = `${compactFormat.format(number / unit[0])}\u00a0${unit[1]}`;
    const full = document.createElement('span');
    full.className = 'sr-only';
    full.textContent = exact;
    cell.append(abbreviated, full);
  }

  function mount() {
    const containers = [...document.querySelectorAll('[data-rs-activity]')];
    // Some CMS editors strip data attributes from the supplied placeholder.
    // Keep this fallback next to our own script, never in an unrelated div.
    if (!containers.length && script.isConnected) {
      const previous = script.previousElementSibling;
      const container = previous?.tagName === 'DIV' && !previous.hasChildNodes()
        ? previous : document.createElement('div');
      if (container !== previous) script.before(container);
      containers.push(container);
    }
    for (const container of containers) {
      if (container.shadowRoot) continue;
      const root = container.attachShadow({mode: 'open'});
      const style = document.createElement('style');
      const section = document.createElement('section');
      style.textContent = `
        :host{display:block;position:relative;container-type:inline-size;font:14px system-ui;color:inherit}
        section{padding:16px;border:1px solid #66717b;border-radius:6px}
        .counts{display:flex;flex-wrap:wrap;align-items:center;gap:6px;padding-right:32px;margin-bottom:14px}
        button{background:transparent;color:inherit;cursor:pointer}
        button:hover,button:focus-visible{color:#dfff63;border-color:#dfff63}
        button:focus-visible{outline:2px solid #dfff63;outline-offset:3px}
        .count{position:relative;display:inline-flex;align-items:center;gap:6px;padding:5px 9px;min-height:30px;border:1px solid #66717b;border-radius:5px;font:650 15px system-ui;font-variant-numeric:tabular-nums}
        .count svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
        .count-tip,.note{border:1px solid #849099;border-radius:8px;background:#171c22;color:#f2f5f7;box-shadow:0 10px 30px #0008;font:13px/1.55 system-ui}
        .count-tip{display:none;position:absolute;z-index:1;top:calc(100% + 5px);left:0;padding:5px 9px;white-space:nowrap;pointer-events:none}
        .count:last-child .count-tip{right:0;left:auto}
        .count:hover .count-tip,.count:focus .count-tip{display:block}
        .activity-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}
        @container (max-width:420px){.activity-grid{grid-template-columns:minmax(0,1fr);gap:14px}}
        h4{margin:0 0 5px;font-size:14px}
        ul{list-style:none;padding:0;margin:0}
        li{padding:8px 0;border-top:1px solid #66717b;overflow-wrap:anywhere}
        small{display:block;margin-top:8px;opacity:.8;overflow-wrap:anywhere}
        .matrix{overflow-x:auto;margin-top:18px}
        table{width:100%;min-width:280px;border-collapse:collapse;font:inherit}
        th,td{padding:9px 4px;border-top:1px solid #515c65;overflow-wrap:anywhere}
        th{font-weight:400;text-align:left}
        thead th{text-align:right;font-size:11px;font-weight:600;overflow-wrap:normal}
        thead th:first-child{width:36%;text-align:left}
        tbody th{font-size:13px}
        td{text-align:right;font-size:16px;font-weight:650;font-variant-numeric:tabular-nums;white-space:nowrap}
        thead th:last-child,td:last-child{font-weight:750;background:#84909912}
        .help{position:absolute;right:14px;top:14px;width:28px;height:28px;border:1px solid #849099;border-radius:50%;font:600 16px system-ui}
        .note{position:fixed;inset:auto;margin:0;box-sizing:border-box;width:440px;max-width:calc(100vw - 24px);padding:14px 16px;overflow:auto;z-index:2147483647}
        .note[hidden],button[hidden]{display:none}
        .sr-only{position:absolute;width:1px;height:1px;padding:0;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
      `;
      section.textContent = 'Loading activity…';
      const counts = document.createElement('div');
      counts.className = 'counts';
      counts.setAttribute('role', 'group');
      counts.setAttribute('aria-label', 'Players online');
      const totalCount = playerCount('total');
      const soloCount = playerCount('solo');
      const multiCount = playerCount('multi');
      counts.append(totalCount.metric, soloCount.metric, multiCount.metric);
      const directory = document.createElement('div');
      const help = document.createElement('button');
      help.type = 'button';
      help.className = 'help';
      help.textContent = 'i';
      help.hidden = true;
      help.setAttribute('aria-label', 'About these statistics');
      help.setAttribute('aria-expanded', 'false');
      help.setAttribute('aria-describedby', 'activity-note');
      const note = document.createElement('div');
      note.id = 'activity-note';
      note.className = 'note';
      note.setAttribute('role', 'tooltip');
      note.popover = 'manual';
      note.hidden = true;
      root.append(style, section, help, note);
      let open = false, pinned = false, hideTimer;
      function positionNote() {
        if (!open) return;
        const card = container.getBoundingClientRect();
        const above = Math.max(0, card.top - 20);
        const below = Math.max(0, window.innerHeight - card.bottom - 20);
        const useOverlay = pinned && Math.max(above, below) < 100;
        note.style.visibility = !pinned && Math.max(above, below) < 100 ? 'hidden' : '';
        note.style.maxHeight = (useOverlay ? window.innerHeight - 24 : Math.max(above, below)) + 'px';
        const box = note.getBoundingClientRect();
        note.style.left = Math.max(12, Math.min(card.left, window.innerWidth - box.width - 12)) + 'px';
        const top = useOverlay ? window.innerHeight - box.height - 12
          : below >= box.height ? card.bottom + 8 : card.top - box.height - 8;
        note.style.top = Math.max(12, top) + 'px';
      }
      function showNote() {
        clearTimeout(hideTimer);
        if (help.hidden || !container.isConnected) return;
        note.hidden = false;
        if (!open && note.showPopover) note.showPopover();
        open = true;
        help.setAttribute('aria-expanded', 'true');
        positionNote();
      }
      function hideNote() {
        clearTimeout(hideTimer);
        if (open && note.hidePopover) note.hidePopover();
        open = false;
        note.hidden = true;
        help.setAttribute('aria-expanded', 'false');
      }
      function leaveNote() {
        hideTimer = setTimeout(() => {
          if (!pinned && root.activeElement !== help) hideNote();
        }, 150);
      }
      function escapeNote(event) {
        if (event.key === 'Escape') { pinned = false; hideNote(); }
      }
      function outsideNote(event) {
        if (open && !event.composedPath().includes(container)) { pinned = false; hideNote(); }
      }
      container.addEventListener('mouseenter', showNote);
      container.addEventListener('mouseleave', leaveNote);
      note.addEventListener('mouseenter', showNote);
      note.addEventListener('mouseleave', leaveNote);
      help.addEventListener('focus', showNote);
      help.addEventListener('blur', leaveNote);
      help.addEventListener('click', () => {
        pinned = !pinned;
        if (pinned) showNote(); else hideNote();
      });
      document.addEventListener('keydown', escapeNote);
      document.addEventListener('pointerdown', outsideNote);
      window.addEventListener('resize', positionNote);
      window.addEventListener('scroll', positionNote, true);
      let running = false;
      async function refresh() {
        if (running || document.hidden || !container.isConnected) return;
        running = true;
        try {
          const response = await fetch(origin + '/api/multiplayer/v2/activity', {credentials:'omit', signal:AbortSignal.timeout(8000)});
          if (!response.ok) throw Error('unavailable');
          const data = await response.json();
          if (data.version !== 2 || !Array.isArray(data.games)) throw Error('version');
          const games = data.games.slice(0, 256);
          const solos = Array.isArray(data.singleplayer) ? data.singleplayer.slice(0, 1024) : [];
          const players = games.reduce((n,g) => n + g.players, 0);
          totalCount.update(players + solos.length, 'active player');
          soloCount.update(solos.length, 'single-player participant');
          multiCount.update(players, 'multiplayer participant');
          const activity = document.createElement('div');
          activity.className = 'activity-grid';
          const multiplayer = document.createElement('div');
          const singleplayer = document.createElement('div');
          activity.append(multiplayer, singleplayer);
          const list = document.createElement('ul');
          for (const game of games.slice(0, 10)) {
            const item = document.createElement('li');
            const mode = {coop:'Co-op', shared:'Competitive Shared', region:'Competitive Region'}[game.mode];
            item.textContent = `${game.locked ? '🔒 ' : ''}${game.city} · ${mode} · ${game.players}/8 · ${game.phase === 'lobby' ? 'Lobby' : 'In progress'}`;
            list.append(item);
          }
          const hint = document.createElement('small');
          hint.textContent = games.length ? 'Join from Multiplayer → Internet in the game.' : 'No public games right now.';
          const multiTitle = document.createElement('h4');
          multiTitle.textContent = 'Multiplayer';
          const soloTitle = document.createElement('h4');
          soloTitle.textContent = 'Single-player';
          const soloList = document.createElement('ul');
          for (const solo of solos.slice(0, 10)) {
            const item = document.createElement('li');
            const population = Number.isSafeInteger(solo.population) && solo.population >= 0
              ? solo.population.toLocaleString('en') : '—';
            item.textContent = `${solo.city} · ${population} residents · ${solo.phase === 'paused' ? 'Paused' : 'In progress'}`;
            soloList.append(item);
          }
          const soloHint = document.createElement('small');
          soloHint.textContent = 'No shared single-player activity right now.';
          multiplayer.append(multiTitle, list, hint);
          singleplayer.append(soloTitle, solos.length ? soloList : soloHint);
          if (section.firstChild !== counts) section.replaceChildren(counts, directory);
          directory.replaceChildren(activity);
          const totals = data.totals;
          if (totals?.available && ['sessions', 'today', 'peak_players'].every(
            key => Number.isSafeInteger(totals[key]) && totals[key] >= 0)) {
            const summary = document.createElement('table');
            summary.setAttribute('aria-label', 'Activity statistics by game type');
            const head = document.createElement('thead');
            const header = document.createElement('tr');
            for (const label of ['Statistics', 'Single-player', 'Multiplayer', 'Total']) {
              const cell = document.createElement('th');
              cell.scope = 'col';
              cell.textContent = label;
              header.append(cell);
            }
            head.append(header);
            const rows = document.createElement('tbody');
            const groups = data.statistics || {multiplayer: totals};
            for (const [key, label] of [['online_players', 'Players online'], ['online_sessions', 'Active sessions'], ['sessions', 'Sessions started'],
              ['today', 'Sessions today (UTC)'], ['peak_players', 'Peak concurrent players'],
              ['cities_founded', 'Cities recorded'], ['total_population', 'Reported population']]) {
              const cell = document.createElement('tr');
              const title = document.createElement('th');
              title.setAttribute('scope', 'row');
              title.textContent = label;
              cell.append(title);
              for (const group of ['singleplayer', 'multiplayer', 'total']) {
                const value = document.createElement('td');
                showNumber(value, groups[group]?.[key]);
                cell.append(value);
              }
              rows.append(cell);
            }
            summary.append(head, rows);
            const matrix = document.createElement('div');
            matrix.className = 'matrix';
            matrix.append(summary);
            note.textContent = `Multiplayer sessions since ${totals.since}. `
              + (groups.singleplayer?.since ? `Single-player reporting since ${groups.singleplayer.since}. ` : '')
              + 'Only reported sessions are included; single-player sharing is optional. Resumed games and reconnects after expiry count as new sessions, not unique people. '
              + 'Saved city IDs prevent double counting, including copied saves. A city played in both modes appears in both columns but once in Total; population uses its latest report, including offline cities. Older saves without an ID must first be saved by a reporting version. '
              + 'The total peak is simultaneous activity, not the sum of the two peaks. Up to ten sessions of each type are listed; counters include all active reports.';
            directory.append(matrix);
            help.hidden = false;
            positionNote();
          } else {
            help.hidden = true;
            pinned = false;
            hideNote();
          }
        } catch {
          section.textContent = 'Activity currently unavailable.';
          help.hidden = true;
          pinned = false;
          hideNote();
        } finally { running = false; }
      }
      refresh();
      const timer = setInterval(() => {
        if (!container.isConnected) {
          clearInterval(timer);
          hideNote();
          document.removeEventListener('keydown', escapeNote);
          document.removeEventListener('pointerdown', outsideNote);
          window.removeEventListener('resize', positionNote);
          window.removeEventListener('scroll', positionNote, true);
          return;
        }
        refresh();
      }, 60000);
    }
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount, {once: true});
  } else {
    mount();
  }
})();
