import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    stages: [
        { duration: '30s', target: 5 },   // Normal load
        { duration: '10s', target: 50 },  // Spike to 50 users
        { duration: '30s', target: 50 },  // Stay at spike
        { duration: '10s', target: 5 },   // Return to normal
        { duration: '30s', target: 5 },   // Stay at normal
    ],
    thresholds: {
        http_req_duration: ['p(95)<2000'],
        http_req_failed: ['rate<0.2'],
    },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';

export default function() {
    let endpoint = ['health', 'orders', 'inventory', 'users'][Math.floor(Math.random() * 4)];
    
    let res = http.get(`${BASE_URL}/api/${endpoint}`);
    check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 2s': (r) => r.timings.duration < 2000,
    });

    sleep(0.5);
}