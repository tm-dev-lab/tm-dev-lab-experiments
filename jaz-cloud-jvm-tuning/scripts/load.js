// k6 load profile for the digital bank: ~70% reads (balance + allocation-heavy statement) and
// ~30% writes (deposit / withdraw / transfer). Account ids span the preloaded range. Business
// rejections (422 insufficient funds) are NOT errors; only 5xx / connection failures are.
import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const N = parseInt(__ENV.PRELOAD_ACCOUNTS || '100000', 10);
const STMT_LIMIT = parseInt(__ENV.STATEMENT_LIMIT || '50', 10);
const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

export const options = {
  vus: parseInt(__ENV.VUS || '100', 10),
  duration: __ENV.DURATION || '60s',
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const serverErrors = new Rate('server_errors');

function randId() {
  return 1 + Math.floor(Math.random() * N);
}

export default function () {
  const r = Math.random();
  let res;
  if (r < 0.45) {
    res = http.get(`${BASE}/api/accounts/${randId()}/statement?limit=${STMT_LIMIT}`);
  } else if (r < 0.70) {
    res = http.get(`${BASE}/api/accounts/${randId()}`);
  } else if (r < 0.82) {
    res = http.post(`${BASE}/api/accounts/${randId()}/deposit`, JSON.stringify({ amountCents: 1000, description: 'load' }), JSON_HEADERS);
  } else if (r < 0.90) {
    res = http.post(`${BASE}/api/accounts/${randId()}/withdraw`, JSON.stringify({ amountCents: 100, description: 'load' }), JSON_HEADERS);
  } else {
    let a = randId();
    let b = randId();
    if (a === b) b = (b % N) + 1;
    res = http.post(`${BASE}/api/transfers`, JSON.stringify({ fromId: a, toId: b, amountCents: 100 }), JSON_HEADERS);
  }
  const ok = res.status >= 200 && res.status < 500;
  serverErrors.add(!ok);
  check(res, { 'status < 500': () => ok });
}

// Version-robust output: write the full summary JSON to SUMMARY_OUT (parsed later) and print one line.
export function handleSummary(data) {
  const out = __ENV.SUMMARY_OUT || 'summary.json';
  const m = data.metrics;
  const d = m.http_req_duration.values;
  const line =
    `reqs=${m.http_reqs.values.count} rate=${m.http_reqs.values.rate.toFixed(1)}/s ` +
    `med=${d.med.toFixed(2)}ms p95=${d['p(95)'].toFixed(2)}ms p99=${d['p(99)'].toFixed(2)}ms ` +
    `srvErr=${(m.server_errors.values.rate * 100).toFixed(2)}%`;
  return { [out]: JSON.stringify(data), stdout: line + '\n' };
}
