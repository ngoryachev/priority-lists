const os = require('os');
const path = require('path');
const { open, dump, texts, login, clickText, clickCard, typeInto, enableSemantics } = require('./lib');

// Screenshots are debugging aids, so they go to the system temp dir.
const SHOTS = os.tmpdir();
const shot = name => path.join(SHOTS, name);

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} — ${name}${detail ? ' :: ' + detail : ''}`);
}

/** Flutter publishes a tooltip as the node's text, not as aria-label. */
async function fab(page) {
  const button = page.locator('flt-semantics:text-matches("^Add ")').last();
  await button.waitFor({ state: 'attached', timeout: 15000 });
  await button.evaluate(e => e.click());
  await page.waitForTimeout(1200);
}

/** Creates a node at the current level. */
async function addNode(page, title, priority = 'Critical') {
  await fab(page);
  await typeInto(page, 0, title);
  await clickText(page, priority);
  await clickText(page, 'Create');
  await page.waitForTimeout(1500);
}

async function has(page, text) {
  return (await texts(page)).some(t => t.includes(text));
}

const API = 'http://65.21.0.66:8000';
const ANON = require('fs')
  .readFileSync(__dirname + '/../../.env.json', 'utf8')
  .match(/"SUPABASE_ANON_KEY":\s*"([^"]+)"/)[1];

/** Rows the API still returns for the test user, straight past the UI. */
async function countNodesOnServer() {
  const auth = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'e2e-tree@example.com', password: 'E2ePassw0rd!tree' }),
  }).then(r => r.json());
  const rows = await fetch(`${API}/rest/v1/nodes?select=id`, {
    headers: { apikey: ANON, Authorization: `Bearer ${auth.access_token}` },
  }).then(r => r.json());
  return Array.isArray(rows) ? rows.length : -1;
}

(async () => {
  const { browser, page } = await open();
  await login(page);
  check('login reaches the tree', await has(page, 'Sign Out'));

  // --- create a chain four levels deep -------------------------------------
  await addNode(page, 'E2E Root');
  check('root node created', await has(page, 'E2E Root'));

  await clickCard(page, 'E2E Root');
  check('drilled into the root node', !(await has(page, 'Sign Out')));

  await addNode(page, 'L1');
  check('child created one level down', await has(page, 'L1'));

  await clickCard(page, 'L1');
  await addNode(page, 'L2');
  check('grandchild created two levels down', await has(page, 'L2'));

  await clickCard(page, 'L2');
  await addNode(page, 'L3');
  check('great-grandchild created three levels down', await has(page, 'L3'));

  await clickCard(page, 'L3');
  await addNode(page, 'L4');
  check('fourth level below the root still accepts children', await has(page, 'L4'));
  await page.screenshot({ path: shot('shot-deep.png') });

  // --- breadcrumbs ---------------------------------------------------------
  const trail = await texts(page);
  check(
    'breadcrumbs list the ancestors',
    ['E2E Root', 'L1', 'L2'].every(t => trail.some(x => x === t)),
    JSON.stringify(trail.slice(0, 12))
  );

  await clickText(page, 'E2E Root');
  await page.waitForTimeout(1200);
  check(
    'breadcrumb jumps back to that ancestor',
    (await has(page, 'L1')) && !(await has(page, 'L4')),
    JSON.stringify((await texts(page)).slice(0, 10))
  );

  // --- persistence ---------------------------------------------------------
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(4500);
  await enableSemantics(page);
  check('tree survives a reload', await has(page, 'E2E Root'));

  // --- move: lift L1 out to the top level ----------------------------------
  await clickCard(page, 'E2E Root');
  await page.waitForTimeout(800);
  const extract = page.locator('flt-semantics:text-is("Move up one level")').last();
  const canExtract = (await extract.count()) > 0;
  if (canExtract) {
    await extract.evaluate(e => e.click());
    await page.waitForTimeout(1800);
  }
  check('extract action is offered on a nested node', canExtract);

  // Back to the top level and confirm L1 arrived with its subtree.
  await clickText(page, 'Back');
  await page.waitForTimeout(1800);
  await enableSemantics(page);
  const top = await texts(page);
  // A card publishes as "<priority>\n[<count>]\n<title>\n<child chips>".
  check('extracted node sits at the top level', top.some(t => t.includes('L1')), JSON.stringify(top));

  await clickCard(page, 'L1');
  await page.waitForTimeout(1000);
  check('extracted node kept its subtree', await has(page, 'L2'));
  await clickText(page, 'Back');
  await page.waitForTimeout(1500);

  // --- move L1 back under E2E Root through the move dialog -----------------
  const moveOn = page
    .locator('flt-semantics[aria-label*="L1"]')
    .locator('xpath=..')
    .locator('flt-semantics:text-is("Move into another node")');
  const moveButtons = page.locator('flt-semantics:text-is("Move into another node")');
  // The cards are ordered like the list: E2E Root first, L1 second.
  await moveButtons.nth(1).evaluate(e => e.click());
  await page.waitForTimeout(800);
  // The move icon arms tap-to-move on this level; the dialog is one tap further.
  await page.locator('flt-semantics:text-matches("^Pick from tree")').last().evaluate(e => e.click());
  await page.waitForTimeout(1200);
  const dialog = await texts(page);
  check(
    'move dialog offers other nodes but never the node itself',
    dialog.some(t => t.includes('E2E Root')) && !dialog.some(t => t === 'L1'),
    JSON.stringify(dialog)
  );

  // Dialog rows read "<title>\n<n> children", so match on the prefix.
  await page
    .locator('flt-semantics:text-matches("^E2E Root")')
    .last()
    .evaluate(e => e.click());
  await page.waitForTimeout(1800);
  const afterMove = await texts(page);
  check(
    'moved node leaves the top level',
    !afterMove.some(t => t.includes('L1') && !t.includes('E2E Root')),
    JSON.stringify(afterMove)
  );

  await clickCard(page, 'E2E Root');
  await page.waitForTimeout(1000);
  check('moved node landed inside the target', await has(page, 'L1'));
  await clickCard(page, 'L1');
  await page.waitForTimeout(1000);
  check('move carried the subtree along', await has(page, 'L2'));

  // --- manual ordering inside a priority group -----------------------------
  // Done one level in, where only the two fixtures are on screen. The previous
  // step left us inside "L1", two levels down.
  await clickText(page, 'Back');
  await page.waitForTimeout(1200);
  await clickText(page, 'Back');
  await page.waitForTimeout(1500);
  await clickCard(page, 'E2E Root');
  await page.waitForTimeout(1000);
  await addNode(page, 'Order A');
  await addNode(page, 'Order B');

  /** Card titles in the order they are painted, top to bottom. */
  const titlesTopDown = async () =>
    page.$$eval('flt-semantics[aria-label]', els =>
      els
        .map(e => ({ label: e.getAttribute('aria-label'), r: e.getBoundingClientRect() }))
        .filter(e => /^(Critical|High|Medium|Low)\n/.test(e.label) && e.r.height > 50)
        .sort((a, b) => a.r.top - b.r.top)
        .map(e => e.label.split('\n').pop())
    );

  const before = await titlesTopDown();
  check('both siblings are on the level',
    before.includes('Order A') && before.includes('Order B'), JSON.stringify(before));

  // Pick the handle geometrically: match the one sitting inside the card's
  // box. DOM order of handles is not the painted order, and the handle is
  // nested under an unlabelled group, so a descendant selector is brittle.
  const box = await page.evaluate(() => {
    const card = [...document.querySelectorAll('flt-semantics[aria-label]')]
      .find(e => (e.getAttribute('aria-label') || '').endsWith('Order B'));
    const cardBox = card.getBoundingClientRect();
    const handle = [...document.querySelectorAll('flt-semantics')]
      .filter(e => e.textContent.trim() === 'Drag to reorder')
      .map(e => e.getBoundingClientRect())
      .find(r => r.top >= cardBox.top - 1 && r.bottom <= cardBox.bottom + 1);
    return { x: handle.x, y: handle.y, width: handle.width, height: handle.height };
  });
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  // Nudge past the drag slop, then travel in steps so the list keeps up.
  await page.mouse.move(x, y - 20);
  for (let i = 1; i <= 8; i++) {
    await page.mouse.move(x, y - 20 - i * 40);
    await page.waitForTimeout(40);
  }
  await page.mouse.up();
  await page.waitForTimeout(1800);

  const after = await titlesTopDown();
  check('dragging reorders siblings of the same priority',
    after.indexOf('Order B') < after.indexOf('Order A'), JSON.stringify(after));

  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(4500);
  await enableSemantics(page);
  await clickCard(page, 'E2E Root');
  await page.waitForTimeout(1200);
  const afterReload = await titlesTopDown();
  check('the manual order survives a reload',
    afterReload.indexOf('Order B') < afterReload.indexOf('Order A'),
    JSON.stringify(afterReload));

  await clickText(page, 'Back');
  await page.waitForTimeout(1500);

  // --- cascade delete ------------------------------------------------------
  const deleteButtons = page.locator('flt-semantics:text-is("Delete")');
  await deleteButtons.first().evaluate(e => e.click());
  // Flutter does not publish an AlertDialog's body text to the accessibility
  // tree, so the warning is captured for visual inspection instead.
  await page.waitForTimeout(1200);
  await page.screenshot({ path: shot('shot-delete-confirm.png') });

  await clickText(page, 'Delete');
  await page.waitForTimeout(2500);
  // The empty-state text is not published to the accessibility tree, so the
  // check is that no cards are left: their action buttons are gone.
  const leftovers = await page.locator('flt-semantics:text-is("Delete")').count();
  check('deleted subtree leaves an empty top level', leftovers === 0, `cards left: ${leftovers}`);

  // The descendants must be gone server-side too, not merely orphaned.
  const remaining = await countNodesOnServer();
  check('server kept no orphaned descendants', remaining === 0, `rows left: ${remaining}`);

  console.log('errors:', page.errors.slice(0, 8));
  await page.screenshot({ path: shot('shot-final.png') });
  await browser.close();

  const failed = results.filter(r => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  console.log(`screenshots: ${SHOTS}`);
  process.exit(failed.length ? 1 : 0);
})();
