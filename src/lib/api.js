// kind: auth | host | host_bug | timeout | spend_limit | rate | overloaded | server | bad_request | network | refused | parse | truncated
// timeout and truncated are not retried: the API may still be generating (and billing) the first attempt.
export class ApiError extends Error {
  constructor(kind, message, status) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

const RETRYABLE = new Set(['rate', 'overloaded', 'server', 'network', 'host']);
const backoff = (attempt) => 1000 * 2 ** attempt;
const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));

function classify(status, body) {
  if (status === 0) {
    const t = body?.error?.type;
    if (t === 'host_config') return 'auth';
    if (t === 'host_timeout') return 'timeout';
    if (t === 'host_error') return 'host_bug'; // a bug in the host, not a transient failure: never retried
    if (t === 'host_network') return 'network';
    return 'host';
  }
  if (status === 401 || status === 403) return 'auth';
  if (status === 429) {
    return body?.error?.details?.error_code === 'enforced_spend_limit_reached' ? 'spend_limit' : 'rate';
  }
  if (status === 529) return 'overloaded';
  if (status >= 500) return 'server';
  return 'bad_request';
}

// transport(body) resolves to { status, retry_after, body } or rejects (ApiError 'host' on port failure).
// onUsage(body) runs once per 2xx body (it was billed), never throws into the call.
export async function callClaude(body, { transport, sleep = realSleep, retries = 2, onUsage } = {}) {
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await transport(body);
    } catch (e) {
      const err = e instanceof ApiError ? e : new ApiError('host', String(e?.message || e));
      if (RETRYABLE.has(err.kind) && attempt < retries) { await sleep(backoff(attempt)); continue; }
      throw err;
    }
    if (res.status >= 200 && res.status < 300) {
      try { onUsage?.(res.body); } catch {} // metering must never break a translation
      return res.body;
    }
    const kind = classify(res.status, res.body);
    if (RETRYABLE.has(kind) && attempt < retries) {
      const ra = Number(res.retry_after);
      await sleep(ra > 0 ? Math.min(ra, 30) * 1000 : backoff(attempt));
      continue;
    }
    throw new ApiError(kind, res.body?.error?.message || `HTTP ${res.status}`, res.status);
  }
}

// parse(resp) returns the value or throws ApiError('parse'). One re-request on parse failure.
export async function callJson(body, parse, opts) {
  try {
    return parse(await callClaude(body, opts));
  } catch (e) {
    if (e.kind !== 'parse') throw e;
    return parse(await callClaude(body, opts));
  }
}
