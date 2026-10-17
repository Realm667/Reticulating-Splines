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
      const section = document.createElement('section');
      section.setAttribute('aria-live', 'polite');
      section.textContent = 'Loading activity…';
      root.append(style, section);
      let running = false;
      async function refresh() {
        if (running || document.hidden || !container.isConnected) return;
        running = true;
        try {
          const response = await fetch(origin + '/api/multiplayer/v1/games', {credentials:'omit', signal:AbortSignal.timeout(8000)});
          if (!response.ok) throw Error('unavailable');
          const data = await response.json();
          if (data.version !== 1 || !Array.isArray(data.games)) throw Error('version');
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
        } catch {
          section.textContent = 'Activity currently unavailable.';
        } finally { running = false; }
      }
      refresh();
      const timer = setInterval(() => {
        if (!container.isConnected) { clearInterval(timer); return; }
        refresh();
      }, 30000);
    }
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount, {once: true});
  } else {
    mount();
  }
})();
