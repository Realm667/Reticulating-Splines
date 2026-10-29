const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const source = readFileSync(`${__dirname}/widgets/activity-v1.js`, 'utf8');

function element(tagName = 'DIV') {
  return {
    tagName, isConnected: true, children: [], textContent: '', shadowRoot: null,
    append(...nodes) { this.children.push(...nodes); },
    replaceChildren(...nodes) { this.children = nodes; },
    setAttribute() {},
    addEventListener() {},
    hasChildNodes() { return this.children.length > 0 || this.textContent !== ''; },
    attachShadow() { assert.equal(this.shadowRoot, null); return this.shadowRoot = element(); },
  };
}

async function fixture({marked = true, loading = false, occupied = false, failure = false, totals, statistics, singleplayer = []} = {}) {
  const container = element();
  if (occupied) container.textContent = 'Existing website content';
  const script = {src: 'https://rs.realm667.com/widgets/activity-v1.js', isConnected: true,
    previousElementSibling: container, before(node) { this.inserted = node; }};
  let ready;
  let requests = 0;
  const document = {currentScript: script, hidden: false, readyState: loading ? 'loading' : 'complete',
    querySelectorAll() { return marked ? [container] : []; },
    createElement: element, addEventListener(event, fn) { if (event === 'DOMContentLoaded') ready = fn; }, removeEventListener() {}};
  const window = {addEventListener() {}, removeEventListener() {}};
  const context = vm.createContext({document, window, URL, AbortSignal, setTimeout, clearTimeout, setInterval() {}, clearInterval() {},
    async fetch(url, options) {
      assert.equal(url, 'https://rs.realm667.com/api/multiplayer/v2/activity');
      assert.equal(options.credentials, 'omit');
      requests++;
      return {ok: !failure, async json() { return {version: 2, games: [], totals, statistics, singleplayer}; }};
    }});
  vm.runInContext(source, context);
  if (loading) { assert.equal(container.shadowRoot, null); ready(); }
  await new Promise(resolve => setImmediate(resolve));
  return {container, script, context, requests};
}

test('standard embed renders empty directory and duplicate script is harmless', async () => {
  const f = await fixture();
  assert.match(f.container.shadowRoot.children[1].children[0].textContent, /0 active players/);
  vm.runInContext(source, f.context);
  assert.equal(f.container.shadowRoot.children.length, 4);
});
test('CMS-stripped attribute uses the adjacent empty placeholder after DOM ready', async () => {
  const f = await fixture({marked: false, loading: true});
  assert.equal(f.requests, 1);
  assert.ok(f.container.shadowRoot);
});
test('fallback preserves existing website content', async () => {
  const f = await fixture({marked: false, occupied: true});
  assert.equal(f.container.shadowRoot, null);
  assert.equal(f.container.textContent, 'Existing website content');
  assert.ok(f.script.inserted.shadowRoot);
});
test('API failure remains visible', async () => {
  const f = await fixture({failure: true});
  assert.equal(f.container.shadowRoot.children[1].textContent, 'Activity currently unavailable.');
});
test('aggregate statistics render separately and tolerate older servers', async () => {
  const f = await fixture({totals: {available: true, sessions: 1234, today: 7, peak_players: 16, since: '2026-10-17'}});
  const section = f.container.shadowRoot.children[1];
  const summary = section.children[6].children[0].children[1];
  assert.deepEqual(summary.children.map(cell => cell.children[2].textContent), ['—', '—', '1,234', '7', '16', '—', '—']);
  assert.ok(summary.children.every(cell => cell.children[1].textContent === '—' && cell.children[3].textContent === '—'));
  assert.match(f.container.shadowRoot.children[3].textContent, /2026-10-17/);
  assert.equal(f.container.shadowRoot.children[3].hidden, true);
  const legacy = await fixture();
  assert.equal(legacy.container.shadowRoot.children[1].children.length, 6);
  const unavailable = await fixture({totals: {available: false}});
  assert.equal(unavailable.container.shadowRoot.children[1].children.length, 6);
});

test('city totals render including genuine zero and reject invalid values', async () => {
  const totals = {available: true, sessions: 12, today: 1, peak_players: 4,
    cities_founded: 0, total_population: 1234567, cities_since: '2026-10-18', since: '2026-10-17'};
  const f = await fixture({totals});
  const rows = value => value.container.shadowRoot.children[1].children[6].children[0].children[1].children;
  assert.deepEqual(rows(f).map(c => c.children[2].textContent), ['—', '—', '12', '1', '4', '0', '1,234,567']);
  const bad = await fixture({totals: {...totals, cities_founded: -1, total_population: '<img>'}});
  assert.deepEqual(rows(bad).slice(5).map(c => c.children[2].textContent), ['—', '—']);
});

test('matrix uses deduplicated total rather than adding game-type cities and peaks', async () => {
  const totals = {available:true, sessions:3, today:1, peak_players:4};
  const statistics = {singleplayer:{cities_founded:7, peak_players:3}, multiplayer:{cities_founded:5, peak_players:4}, total:{cities_founded:10, peak_players:6}};
  const f = await fixture({totals, statistics, singleplayer:[{city:'<script>not markup</script>',population:0,phase:'paused'}]});
  const section = f.container.shadowRoot.children[1];
  assert.match(section.children[0].textContent, /1 active players/);
  assert.equal(section.children[5].children[0].textContent, '<script>not markup</script> · 0 residents · Paused');
  const rows = section.children[6].children[0].children[1].children;
  assert.deepEqual(rows[5].children.slice(1).map(c => c.textContent), ['7','5','10']);
  assert.deepEqual(rows[4].children.slice(1).map(c => c.textContent), ['3','4','6']);
});
