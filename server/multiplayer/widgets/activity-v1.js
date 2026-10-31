/* Public activity only; no credentials, IP addresses or player rosters. */
(() => {
  const script = document.currentScript;
  const origin = new URL(script.src).origin;
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
      style.textContent = ':host{display:block;font:14px system-ui;color:inherit}section{padding:16px;border:1px solid #66717b;border-radius:6px}h3{margin:0 0 12px;font-size:16px}ul{list-style:none;padding:0;margin:0}li{padding:8px 0;border-top:1px solid #66717b}small{opacity:.8}';
      style.textContent += ':host{position:relative}h3{padding-right:30px}table{width:100%;border-collapse:collapse;margin-top:18px;font:inherit}th,td{padding:9px 0;border-top:1px solid #515c65}th{font-weight:400;text-align:left;padding-right:16px}td{text-align:right;font-size:19px;font-weight:650;font-variant-numeric:tabular-nums;white-space:nowrap}button{position:absolute;right:14px;top:14px;width:28px;height:28px;border:1px solid #849099;border-radius:50%;background:transparent;color:inherit;font:600 16px system-ui;cursor:pointer}button:hover,button:focus-visible{color:#dfff63;border-color:#dfff63}button:focus-visible{outline:2px solid #dfff63;outline-offset:3px}.note{position:fixed;inset:auto;margin:0;box-sizing:border-box;width:440px;max-width:calc(100vw - 24px);padding:14px 16px;border:1px solid #849099;border-radius:8px;background:#171c22;color:#f2f5f7;box-shadow:0 10px 30px #0008;font:13px/1.55 system-ui;overflow:auto;z-index:2147483647}.note[hidden],button[hidden]{display:none}';
      const section = document.createElement('section');
      style.textContent += 'h4{margin:14px 0 5px;font-size:14px}.matrix{overflow-x:auto;margin-top:18px}table{margin-top:0;table-layout:auto;min-width:300px}thead th{text-align:right;font-size:11px;font-weight:600;overflow-wrap:normal}thead th:first-child{width:36%;text-align:left}th,td{padding:9px 4px;overflow-wrap:anywhere}tbody th{font-size:13px}td{font-size:16px;white-space:nowrap}thead th:last-child,td:last-child{font-weight:750;background:#84909912}small{display:block;margin-top:8px}';
      section.setAttribute('aria-live', 'polite');
      section.textContent = 'Loading activity…';
      const help = document.createElement('button');
      help.type = 'button';
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
        note.style.maxHeight = Math.max(80, window.innerHeight - 24) + 'px';
        const box = note.getBoundingClientRect();
        note.style.left = Math.max(12, Math.min(card.left, window.innerWidth - box.width - 12)) + 'px';
        const below = card.bottom + 8;
        note.style.top = Math.max(12, below + box.height <= window.innerHeight - 12
          ? below : Math.min(card.top - box.height - 8, window.innerHeight - box.height - 12)) + 'px';
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
          const heading = document.createElement('h3');
          const players = games.reduce((n,g) => n + g.players, 0);
          heading.textContent = `${players + solos.length} active players · ${solos.length} single-player · ${players} multiplayer`;
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
          if (!solos.length) {
            const item = document.createElement('li');
            item.textContent = 'No shared single-player activity right now.';
            item.style.fontSize = 'smaller';
            soloList.append(item);
          }
          section.replaceChildren(heading, multiTitle, list, hint, soloTitle, soloList);
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
                const number = groups[group]?.[key];
                value.textContent = Number.isSafeInteger(number) && number >= 0 ? number.toLocaleString('en') : '—';
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
            section.append(matrix);
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
