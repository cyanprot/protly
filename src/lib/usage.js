// Token usage and cost, recorded from every 2xx API body (see callClaude's onUsage).
// Prices in US$ per million tokens, checked 2026-10-28 on https://platform.claude.com/docs/en/about-claude/pricing.
export const PRICES = {
  'claude-sonnet-5-5': { input: 2, output: 10, cache_read: 0.1, cache_5m: 2.5, cache_1h: 4 },
  'claude-opus-5-5': { input: 4, output: 20, cache_read: 0.2, cache_5m: 5, cache_1h: 8 },
};
export const KEEP_DAYS = 62;
const FIELDS = ['input', 'output', 'cache_read', 'cache_5m', 'cache_1h'];
const DAY_MS = 24 * 60 * 60 * 1000;
const count = (v) => (Number.isFinite(v) && v > 0 ? v : 0);

export function tokensOf(body) {
  const u = body?.usage || {};
  const split = u.cache_creation;
  const hasSplit = split && (typeof split.ephemeral_5m_input_tokens === 'number'
    || typeof split.ephemeral_1h_input_tokens === 'number');
  return {
    input: count(u.input_tokens),
    output: count(u.output_tokens),
    cache_read: count(u.cache_read_input_tokens),
    // No breakdown: count every cache write at the 5m rate.
    cache_5m: hasSplit ? count(split.ephemeral_5m_input_tokens) : count(u.cache_creation_input_tokens),
    cache_1h: hasSplit ? count(split.ephemeral_1h_input_tokens) : 0,
  };
}

// Exact id, or a dated variant of a known id ("claude-opus-5-5-20261001").
function priceFor(model) {
  if (typeof model !== 'string') return null;
  if (PRICES[model]) return PRICES[model];
  const base = Object.keys(PRICES).find((k) => model.startsWith(`${k}-`));
  return base ? PRICES[base] : null;
}

// US$ for one usage entry, or null when the model has no price.
export function costOf(entry, model) {
  const p = priceFor(model);
  if (!p) return null;
  return FIELDS.reduce((sum, f) => sum + (count(entry?.[f]) * p[f]) / 1e6, 0);
}

export function localDate(ms) {
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function prune(usage, now) {
  const cutoff = localDate(now - KEEP_DAYS * DAY_MS);
  for (const day of Object.keys(usage)) if (day < cutoff) delete usage[day];
}

// get() returns the stored usage object (or undefined); set(usage) stores it.
// Writes run one at a time so concurrent API calls never lose an increment.
export function createUsageRecorder({ get, set, now = Date.now }) {
  let chain = Promise.resolve();
  function record(body) {
    const model = typeof body?.model === 'string' && body.model ? body.model : 'unknown';
    const tokens = tokensOf(body);
    chain = chain.then(async () => {
      const usage = (await get()) || {};
      const t = now();
      const day = (usage[localDate(t)] ??= {});
      const e = (day[model] ??= { calls: 0, input: 0, output: 0, cache_read: 0, cache_5m: 0, cache_1h: 0 });
      e.calls += 1;
      for (const f of FIELDS) e[f] = count(e[f]) + tokens[f];
      prune(usage, t);
      await set(usage);
    }).catch((err) => console.warn('[protly] usage write failed', err));
    return chain;
  }
  return { record };
}

// { today, month } in US$ (local calendar), unpriced: a model this month had no price.
export function summarize(usage, now) {
  const today = localDate(now);
  const month = today.slice(0, 8); // "YYYY-MM-"
  const out = { today: 0, month: 0, unpriced: false };
  for (const [day, models] of Object.entries(usage || {})) {
    if (!day.startsWith(month)) continue;
    for (const [model, entry] of Object.entries(models)) {
      const c = costOf(entry, model);
      if (c == null) { if (entry?.calls) out.unpriced = true; continue; }
      out.month += c;
      if (day === today) out.today += c;
    }
  }
  return out;
}

export function formatUsd(n, unpriced = false) {
  const s = n > 0 && n < 0.005 ? '<$0.01' : `$${n.toFixed(2)}`;
  return unpriced ? `${s} ?` : s;
}
