// Mobile-web pass over the deployed app: a real phone viewport, touch input
// instead of synthetic clicks, and a check that nothing overflows or is left
// under the minimum tap size.
const os = require('os');
const path = require('path');
const { devices, chromium } = require('playwright');
const { dump, texts, ensureAccount, resetTree } = require('./lib');

const URL = 'http://65.21.0.66:8000/';
const EMAIL = process.env.E2E_EMAIL || 'e2e-mobile@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'E2ePassw0rd!mobile';
const SHOTS = os.tmpdir();

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} — ${name}${detail ? ' :: ' + detail : ''}`);
}

/**
 * Flutter only publishes its accessibility tree after a real gesture on the
 * hidden placeholder — a synthetic `click()` is ignored on a touch device.
 */
async function enableSemanticsByTouch(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  // The placeholder is removed once semantics are on, so this is a no-op after
  // the first call.
  if ((await placeholder.count()) === 0) return;
  const box = await placeholder.boundingBox();
  if (!box) return;
  await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(1500);
}

/** Taps the element's centre with a real touch event. */
async function tap(page, locator) {
  const box = await locator.boundingBox();
  if (!box) throw new Error('element has no box: ' + locator);
  await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(900);
}

function leaf(page, text) {
  return page.locator(`flt-semantics:text-is(${JSON.stringify(text)})`).last();
}

function card(page, title) {
  return page.locator(`flt-semantics[aria-label*=${JSON.stringify(title)}]`).first();
}

async function typeInto(page, index, value) {
  const input = page.locator('flt-semantics input').nth(index);
  await input.waitFor({ timeout: 15000 });
  await tap(page, input);
  await page.keyboard.type(value, { delay: 15 });
  await page.waitForTimeout(300);
}

async function addNode(page, title, priority = 'Critical') {
  await tap(page, page.locator('flt-semantics:text-matches("^Add ")').last());
  await typeInto(page, 0, title);
  await tap(page, leaf(page, priority));
  await tap(page, leaf(page, 'Create'));
  await page.waitForTimeout(1400);
}

/** Interactive elements smaller than 44x44 CSS px are hard to hit on a phone. */
async function smallTapTargets(page, selector = 'flt-semantics[role=button]') {
  return page.$$eval(selector, els =>
    els
      .map(e => ({ label: (e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 30), r: e.getBoundingClientRect() }))
      .filter(e => e.r.width > 0 && e.r.height > 0 && (e.r.width < 44 || e.r.height < 44))
      .map(e => `${e.label || '(unlabelled)'} ${Math.round(e.r.width)}x${Math.round(e.r.height)}`)
  );
}

/** Sizes of the breadcrumb crumbs, which are how you climb back up the tree. */
async function crumbSizes(page) {
  return page.$$eval('flt-semantics[role=button]', els =>
    els
      .map(e => ({ label: (e.textContent || '').trim(), r: e.getBoundingClientRect() }))
      // The trail sits directly under the app bar, above any card.
      .filter(e => e.r.top > 40 && e.r.top < 130 && e.r.height > 0)
      .map(e => `${e.label} ${Math.round(e.r.width)}x${Math.round(e.r.height)}`)
  );
}

/** Content wider than the viewport means a horizontal scrollbar on a phone. */
async function overflowsHorizontally(page) {
  return page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
}

(async () => {
  await ensureAccount(EMAIL, PASSWORD);
  await resetTree(EMAIL, PASSWORD);
  const browser = await chromium.launch({ channel: 'chrome' });
  const phone = devices['Pixel 7'];
  const context = await browser.newContext({ ...phone });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));

  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForTimeout(4000);
  await enableSemanticsByTouch(page);
  console.log(`viewport: ${JSON.stringify(page.viewportSize())}, touch: ${phone.hasTouch}, dpr: ${phone.deviceScaleFactor}`);

  check('app boots on a phone viewport', (await texts(page)).some(t => t.includes('Sign In')));

  // --- sign in with touch ---------------------------------------------------
  await typeInto(page, 0, EMAIL);
  await typeInto(page, 1, PASSWORD);
  await tap(page, leaf(page, 'Sign In'));
  await page.waitForTimeout(5000);
  await enableSemanticsByTouch(page);
  check('touch sign-in reaches the tree', (await texts(page)).some(t => t.includes('Sign Out')));
  await page.screenshot({ path: path.join(SHOTS, 'mobile-top.png') });

  // --- build a deep chain by touch -----------------------------------------
  await addNode(page, 'Mobile Root');
  check('created a node by touch', (await texts(page)).some(t => t.includes('Mobile Root')));

  await tap(page, card(page, 'Mobile Root'));
  await addNode(page, 'M1');
  await tap(page, card(page, 'M1'));
  await addNode(page, 'M2');
  await tap(page, card(page, 'M2'));
  await addNode(page, 'M3');
  check('drilled three levels down by touch', (await texts(page)).some(t => t.includes('M3')));
  await page.screenshot({ path: path.join(SHOTS, 'mobile-deep.png') });

  check('no horizontal overflow at depth', !(await overflowsHorizontally(page)));

  // The breadcrumbs are new with the tree, so they are held to the 44px rule.
  const crumbBoxes = await crumbSizes(page);
  const tooSmallCrumbs = crumbBoxes.filter(c => {
    const [w, h] = c.split(' ').pop().split('x').map(Number);
    return w < 44 || h < 44;
  });
  check('every breadcrumb clears a 44px tap target', tooSmallCrumbs.length === 0,
    JSON.stringify(crumbBoxes));

  // The dense card/app-bar controls predate the tree; reported, not asserted.
  const small = await smallTapTargets(page);
  console.log(`note — controls under 44px (pre-existing): ${JSON.stringify(small)}`);

  // --- breadcrumbs are reachable on a narrow bar ----------------------------
  const crumbs = await texts(page);
  check(
    'breadcrumbs stay usable on a narrow screen',
    ['Mobile Root', 'M1'].every(t => crumbs.includes(t)),
    JSON.stringify(crumbs.filter(t => !t.includes('\n')).slice(0, 8))
  );
  await tap(page, leaf(page, 'Mobile Root'));
  check('breadcrumb tap navigates', (await texts(page)).some(t => t.includes('M1')));

  // --- the move dialog on a small screen ------------------------------------
  await tap(page, page.locator('flt-semantics:text-is("Move into another node")').first());
  await page.waitForTimeout(1200);
  await page.screenshot({ path: path.join(SHOTS, 'mobile-move.png') });
  const dialog = await texts(page);
  // The current parent is rendered disabled, and a disabled ListTile is not
  // published to the accessibility tree — "Top level" is the reachable target.
  check('move dialog fits and offers a destination', dialog.some(t => t.includes('Top level')), JSON.stringify(dialog));
  check('move dialog does not overflow', !(await overflowsHorizontally(page)));
  await tap(page, leaf(page, 'Cancel'));

  // --- landscape ------------------------------------------------------------
  await page.setViewportSize({ width: 851, height: 393 });
  await page.waitForTimeout(1500);
  await enableSemanticsByTouch(page);
  check('landscape renders without overflow', !(await overflowsHorizontally(page)));
  await page.screenshot({ path: path.join(SHOTS, 'mobile-landscape.png') });

  // --- clean up -------------------------------------------------------------
  await page.setViewportSize({ width: phone.viewport.width, height: phone.viewport.height });
  await page.waitForTimeout(1200);
  await enableSemanticsByTouch(page);
  // After a resize the back arrow is published as "Back\nBack", so match a prefix.
  await tap(page, page.locator('flt-semantics:text-matches("^Back")').last());
  await page.waitForTimeout(1200);
  await tap(page, page.locator('flt-semantics:text-is("Delete")').first());
  await page.waitForTimeout(1000);
  await tap(page, leaf(page, 'Delete'));
  await page.waitForTimeout(2000);
  check('cleanup left the top level empty', (await page.locator('flt-semantics:text-is("Delete")').count()) === 0);

  console.log('page errors:', errors.slice(0, 5));
  await browser.close();

  const failed = results.filter(r => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  console.log(`screenshots: ${SHOTS}`);
  process.exit(failed.length ? 1 : 0);
})();
