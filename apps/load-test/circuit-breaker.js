import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    vus: 30,
    duration: '2m',
    thresholds: {
        http_req_duration: ['p(95)<3000'],
        // Allow higher error rate for circuit breaker testing
        http_req_failed: ['rate<0.5'],
    },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';

export default function() {
    // Aggressive load to trigger circuit breaker
    let responses = http.batch([
        ['GET', `${BASE_URL}/api/orders`],
        ['GET', `${BASE_URL}/api/inventory`],
        ['GET', `${BASE_URL}/api/users`],
        ['GET', `${BASE_URL}/api/orders`],
        ['GET', `${BASE_URL}/api/inventory`],
    ]);

    for (let i = 0; i < responses.length; i++) {
        check(responses[i], {
            'request completed': (r) => r.status !== 0,
        });
    }

    // Create multiple orders rapidly
    for (let i = 0; i < 3; i++) {
        let orderData = {
            user_id: Math.floor(Math.random() * 5) + 1,
            product_id: Math.floor(Math.random() * 5) + 1,
            quantity: Math.floor(Math.random() * 5) + 1
        };

        http.post(`${BASE_URL}/api/orders`, JSON.stringify(orderData), {
            headers: { 'Content-Type': 'application/json' },
        });
    }

    sleep(0.1); // Very short sleep for aggressive load
}