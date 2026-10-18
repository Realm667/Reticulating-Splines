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
      style.textContent += 'dl{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:12px;margin:18px 0 8px;padding-top:14px;border-top:1px solid #66717b}dt{font-size:12px;opacity:.8}dd{margin:4px 0 0;font-size:23px;font-weight:650;font-variant-numeric:tabular-nums}';
      const section = document.createElement('section');
      section.setAttribute('aria-live', 'polite');
      section.textContent = 'Loading activity…';
      root.append(style, section);
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
          const heading = document.createElement('h3');
          heading.textContent = `${games.reduce((n,g) => n + g.players, 0)} players online · ${games.length} games`;
          const list = document.createElement('ul');
          for (const game of games.slice(0, 10)) {
            const item = document.createElement('li');
            const mode = {coop:'Co-op', shared:'Competitive Shared', region:'Competitive Region'}[game.mode];
            item.textContent = `${game.locked ? '🔒 ' : ''}${game.city} · ${mode} · ${game.players}/8 · ${game.phase === 'lobby' ? 'Lobby' : 'In progress'}`;
            list.append(item);
          }
          const hint = document.createElement('small');
          hint.textContent = games.length ? 'Join from Multiplayer → Internet in the game.' : 'No public games right now.';
          section.replaceChildren(heading, list, hint);
          const totals = data.totals;
          if (totals?.available && ['sessions', 'today', 'peak_players'].every(
            key => Number.isSafeInteger(totals[key]) && totals[key] >= 0)) {
            const summary = document.createElement('dl');
            summary.setAttribute('aria-label', 'Totals');
            for (const [key, label] of [['sessions', 'Sessions started'],
              ['today', 'Sessions today (UTC)'], ['peak_players', 'Peak concurrent players'],
              ['cities_founded', 'Cities founded'], ['total_population', 'Total population']]) {
              const cell = document.createElement('div');
              const title = document.createElement('dt');
              title.textContent = label;
              const value = document.createElement('dd');
              value.textContent = Number.isSafeInteger(totals[key]) && totals[key] >= 0
                ? totals[key].toLocaleString('en') : '—';
              cell.append(title, value);
              summary.append(cell);
            }
            const note = document.createElement('small');
            note.textContent = `Sessions since ${totals.since} · Online play only; resumed games count as new sessions. `
              + (totals.cities_since ? `City reporting since ${totals.cities_since}. ` : '')
              + 'Cities are counted once; population reflects each city’s latest reported total. Requires a game version with city reporting; earlier and offline play are not included.';
            section.append(summary, note);
          }
        } catch {
          section.textContent = 'Activity currently unavailable.';
        } finally { running = false; }
      }
      refresh();
      const timer = setInterval(() => {
        if (!container.isConnected) { clearInterval(timer); return; }
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
