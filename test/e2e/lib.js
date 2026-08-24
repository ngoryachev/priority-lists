const { chromium } = require('playwright');

const URL = 'http://65.21.0.66:8000/';
const EMAIL = 'e2e-tree@example.com';
const PASSWORD = 'E2ePassw0rd!tree';
const ANON = require('fs')
  .readFileSync(__dirname + '/../../.env.json', 'utf8')
  .match(/"SUPABASE_ANON_KEY":\s*"([^"]+)"/)[1];

/**
 * Signs the throwaway account up if it does not exist yet, so a run never
 * depends on an account someone provisioned by hand.
 */
async function ensureAccount(email = EMAIL, password = PASSWORD) {
  const res = await fetch(`${URL}auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const body = await res.json().catch(() => ({}));
  // "User already registered" is the expected outcome on every run but the first.
  if (!res.ok && !/already/i.test(JSON.stringify(body))) {
    throw new Error(`could not provision ${email}: ${JSON.stringify(body)}`);
  }
}

/** Token for the throwaway account, for the API-side setup and assertions. */
async function accessToken(email = EMAIL, password = PASSWORD) {
  const res = await fetch(`${URL}auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const body = await res.json();
  if (!body.access_token) throw new Error(`sign-in failed: ${JSON.stringify(body)}`);
  return body.access_token;
}

/**
 * Empties the account's tree before a run. Without this an interrupted run
 * leaves nodes behind and the next one asserts against someone else's mess.
 */
async function resetTree(email = EMAIL, password = PASSWORD) {
  const token = await accessToken(email, password);
  const me = await fetch(`${URL}auth/v1/user`, {
    headers: { apikey: ANON, Authorization: `Bearer ${token}` },
  }).then(r => r.json());
  await fetch(`${URL}rest/v1/nodes?user_id=eq.${me.id}`, {
    method: 'DELETE',
    headers: { apikey: ANON, Authorization: `Bearer ${token}` },
  });
}

async function open() {
  await ensureAccount();
  await resetTree();
  const browser = await chromium.launch({ channel: 'chrome' });
  const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.errors = errors;
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForTimeout(3500);
  await enableSemantics(page);
  return { browser, page };
}

async function enableSemantics(page) {
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) p.click();
  });
  await page.waitForTimeout(1200);
}

/** Dump of the accessibility tree Flutter publishes into the DOM. */
async function dump(page) {
  return page.$$eval('flt-semantics', els =>
    els
      .map(e => ({
        role: e.getAttribute('role'),
        label: e.getAttribute('aria-label'),
        tag: e.firstElementChild ? e.firstElementChild.tagName : null,
        text: (e.childElementCount === 0 ? e.textContent : '').trim().slice(0, 60),
      }))
      .filter(e => e.text || e.label || e.role === 'button' || e.tag === 'INPUT' || e.tag === 'TEXTAREA')
  );
}

/** Leaf semantics node carrying exactly this text. */
function leaf(page, text) {
  return page.locator(`flt-semantics:text-is(${JSON.stringify(text)})`).last();
}

async function clickText(page, text, { timeout = 8000 } = {}) {
  const el = leaf(page, text);
  await el.waitFor({ state: 'attached', timeout });
  await el.evaluate(e => e.click());
  await page.waitForTimeout(700);
}

async function clickLabel(page, label, { timeout = 8000 } = {}) {
  const el = page.locator(`flt-semantics[aria-label=${JSON.stringify(label)}]`).last();
  await el.waitFor({ state: 'attached', timeout });
  await el.evaluate(e => e.click());
  await page.waitForTimeout(700);
}

/** A card publishes itself as one semantics node labelled "<priority>\n<title>". */
async function clickCard(page, title, { timeout = 10000 } = {}) {
  const card = page.locator(`flt-semantics[aria-label*=${JSON.stringify(title)}]`).first();
  await card.waitFor({ state: 'attached', timeout });
  await card.evaluate(e => e.click());
  await page.waitForTimeout(1200);
}

/** Every label and leaf text currently on screen. */
async function texts(page) {
  return (await dump(page)).map(e => e.label || e.text).filter(Boolean);
}

/** Types into the nth text field: Flutter only syncs the focused input. */
async function typeInto(page, index, value) {
  const input = page.locator('flt-semantics input').nth(index);
  await input.waitFor({ timeout: 15000 });
  await input.click();
  await page.waitForTimeout(300);
  await page.keyboard.type(value, { delay: 15 });
  await page.waitForTimeout(300);
}

async function login(page) {
  await typeInto(page, 0, EMAIL);
  await typeInto(page, 1, PASSWORD);
  await clickText(page, 'Sign In');
  await page.waitForTimeout(5000);
  await enableSemantics(page);
}

module.exports = { open, dump, texts, clickText, clickCard, clickLabel, login, leaf, typeInto, enableSemantics, ensureAccount, accessToken, resetTree, EMAIL, PASSWORD };
