// k6 Load Test - Single Chat Message Send
// Usage: k6 run -e IM_HOST=192.168.1.100 -e IM_PORT=80 k6_single_chat.js

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const IM_HOST = __ENV.IM_HOST || 'localhost';
const IM_PORT = __ENV.IM_PORT || '80';
const BASE_URL = `http://${IM_HOST}:${IM_PORT}`;
const ADMIN_PORT = __ENV.ADMIN_PORT || '18080';
const ADMIN_URL = `http://${IM_HOST}:${ADMIN_PORT}`;
const DURATION = parseInt(__ENV.DURATION || '60');
const VUS = parseInt(__ENV.VUS || '50');

export const options = {
  stages: [
    { duration: '10s', target: VUS / 2 },
    { duration: '20s', target: VUS },
    { duration: `${DURATION}s`, target: VUS },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.95'],
  },
};

export function setup() {
  const res = http.get(`${ADMIN_URL}/api/version`);
  check(res, { 'IM service reachable': (r) => r.status === 200 });
  return { startTime: Date.now() };
}

export default function () {
  group('send message', function () {
    const msgId = `${__VU}-${__ITER}-${Date.now()}`;
    const payload = JSON.stringify({
      sender: `perf_sender_${msgId}`,
      target: `perf_target_${msgId}`,
      content: { type: 1, searchableContent: `perf-test-msg-${msgId}` },
    });

    const res = http.post(`${BASE_URL}/api/message/send`, payload, {
      headers: { 'Content-Type': 'application/json' },
      tags: { name: 'sendMessage' },
    });

    check(res, {
      'status 200': (r) => r.status === 200,
      'response has messageUid': (r) => r.json().messageUid !== undefined,
    });
  });

  sleep(0.1);
}

export function teardown(data) {
  const elapsed = (Date.now() - data.startTime) / 1000;
  console.log(`Test completed in ${elapsed.toFixed(1)}s`);
}
