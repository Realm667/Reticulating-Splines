const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const source = readFileSync(`${__dirname}/widgets/activity-v1.js`, 'utf8');

function element(tagName = 'DIV') {
  return {
    tagName, isConnected: true, children: [], attributes: {}, textContent: '', shadowRoot: null,
    get firstChild() { return this.children[0]; },
    append(...nodes) { this.children.push(...nodes); },
    replaceChildren(...nodes) { this.children = nodes; },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener() {},
    hasChildNodes() { return this.children.length > 0 || this.textContent !== ''; },
    attachShadow() { assert.equal(this.shadowRoot, null); return this.shadowRoot = element(); },
  };
}

async function fixture({marked = true, loading = false, occupied = false, failure = false, totals, statistics, games = [], singleplayer = []} = {}) {
  const container = element();
  if (occupied) container.textContent = 'Existing website content';
  const script = {src: 'https://rs.realm667.com/widgets/activity-v1.js', isConnected: true,
    previousElementSibling: container, before(node) { this.inserted = node; }};
  let ready;
  let requests = 0;
  const document = {currentScript: script, hidden: false, readyState: loading ? 'loading' : 'complete',
    querySelectorAll() { return marked ? [container] : []; },
    createElement: element, createElementNS(_namespace, tag) { return element(tag); },
    addEventListener(event, fn) { if (event === 'DOMContentLoaded') ready = fn; }, removeEventListener() {}};
  const window = {addEventListener() {}, removeEventListener() {}};
  const context = vm.createContext({document, window, URL, AbortSignal, setTimeout, clearTimeout, setInterval() {}, clearInterval() {},
    async fetch(url, options) {
      assert.equal(url, 'https://rs.realm667.com/api/multiplayer/v2/activity');
      assert.equal(options.credentials, 'omit');
      requests++;
      return {ok: !failure, async json() { return {version: 2, games, totals, statistics, singleplayer}; }};
    }});
  vm.runInContext(source, context);
  if (loading) { assert.equal(container.shadowRoot, null); ready(); }
  await new Promise(resolve => setImmediate(resolve));
  return {container, script, context, requests};
}

const panel = f => f.container.shadowRoot.children[1];
const directory = f => panel(f).children[1];
const rows = f => directory(f).children[1].children[0].children[1].children;
const displayed = cell => cell.children[0]?.textContent ?? cell.textContent;

test('standard embed renders empty directory and duplicate script is harmless', async () => {
  const f = await fixture();
  const counts = panel(f).children[0].children;
  assert.deepEqual(counts.map(count => count.attributes['aria-label']), ['0 active players', '0 single-player participants', '0 multiplayer participants']);
  assert.ok(counts.every(count => count.children[0].tagName === 'svg' && count.children[1].textContent === '0'));
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
  assert.deepEqual(rows(f).map(cell => cell.children[2].textContent), ['—', '—', '1,234', '7', '16', '—', '—']);
  assert.ok(rows(f).every(cell => cell.children[1].textContent === '—' && cell.children[3].textContent === '—'));
  assert.match(f.container.shadowRoot.children[3].textContent, /2026-10-17/);
  assert.equal(f.container.shadowRoot.children[3].hidden, true);
  const legacy = await fixture();
  assert.equal(directory(legacy).children.length, 1);
  const unavailable = await fixture({totals: {available: false}});
  assert.equal(directory(unavailable).children.length, 1);
});

test('city totals render including genuine zero and reject invalid values', async () => {
  const totals = {available: true, sessions: 12, today: 1, peak_players: 4,
    cities_founded: 0, total_population: 1234567, cities_since: '2026-10-18', since: '2026-10-17'};
  const f = await fixture({totals});
  assert.deepEqual(rows(f).map(c => displayed(c.children[2])), ['—', '—', '12', '1', '4', '0', '1,234.6\u00a0K']);
  const bad = await fixture({totals: {...totals, cities_founded: -1, total_population: '<img>'}});
  assert.deepEqual(rows(bad).slice(5).map(c => c.children[2].textContent), ['—', '—']);
});

test('matrix uses deduplicated total rather than adding game-type cities and peaks', async () => {
  const totals = {available:true, sessions:3, today:1, peak_players:4};
  const statistics = {singleplayer:{cities_founded:7, peak_players:3}, multiplayer:{cities_founded:5, peak_players:4}, total:{cities_founded:10, peak_players:6}};
  const f = await fixture({totals, statistics, singleplayer:[{city:'<script>not markup</script>',population:0,phase:'paused'}]});
  assert.equal(panel(f).children[0].children[0].attributes['aria-label'], '1 active player');
  const [multi, solo] = directory(f).children[0].children;
  assert.equal(multi.children[2].textContent, 'No public games right now.');
  assert.equal(solo.children[1].children[0].textContent, '<script>not markup</script> · 0 residents · Paused');
  assert.deepEqual(rows(f)[5].children.slice(1).map(c => c.textContent), ['7','5','10']);
  assert.deepEqual(rows(f)[4].children.slice(1).map(c => c.textContent), ['3','4','6']);
});

test('statistics switch at the requested thresholds and retain the precise value', async () => {
  const totals = {available: true, sessions: 9_999, today: 10_000, peak_players: 10_000_000, total_population: 40_705_185};
  const f = await fixture({totals});
  const values = rows(f).map(row => row.children[2]);
  assert.deepEqual(values.map(displayed), ['—', '—', '9,999', '10\u00a0K', '10\u00a0M', '—', '40.7\u00a0M']);
  assert.equal(values[6].title, '40,705,185');
  assert.equal(values[6].children[1].textContent, '40,705,185');
});
