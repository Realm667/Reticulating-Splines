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
    hasChildNodes() { return this.children.length > 0 || this.textContent !== ''; },
    attachShadow() { assert.equal(this.shadowRoot, null); return this.shadowRoot = element(); },
  };
}

async function fixture({marked = true, loading = false, occupied = false, failure = false} = {}) {
  const container = element();
  if (occupied) container.textContent = 'Existing website content';
  const script = {src: 'https://rs.realm667.com/widgets/activity-v1.js', isConnected: true,
    previousElementSibling: container, before(node) { this.inserted = node; }};
  let ready;
  let requests = 0;
  const document = {currentScript: script, hidden: false, readyState: loading ? 'loading' : 'complete',
    querySelectorAll() { return marked ? [container] : []; },
    createElement: element, addEventListener(event, fn) { assert.equal(event, 'DOMContentLoaded'); ready = fn; }};
  const context = vm.createContext({document, URL, AbortSignal, setInterval() {}, clearInterval() {},
    async fetch(url, options) {
      assert.equal(url, 'https://rs.realm667.com/api/multiplayer/v1/games');
      assert.equal(options.credentials, 'omit');
      requests++;
      return {ok: !failure, async json() { return {version: 1, games: []}; }};
    }});
  vm.runInContext(source, context);
  if (loading) { assert.equal(container.shadowRoot, null); ready(); }
  await new Promise(resolve => setImmediate(resolve));
  return {container, script, context, requests};
}

test('standard embed renders empty directory and duplicate script is harmless', async () => {
  const f = await fixture();
  assert.match(f.container.shadowRoot.children[1].children[0].textContent, /0 players online/);
  vm.runInContext(source, f.context);
  assert.equal(f.container.shadowRoot.children.length, 2);
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
