import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    stages: [
        { duration: '30s', target: 5 },   // Ramp up to 5 users
        { duration: '1m', target: 10 },   // Stay at 10 users
        { duration: '30s', target: 20 },  // Ramp up to 20 users
        { duration: '1m', target: 20 },   // Stay at 20 users
        { duration: '30s', target: 0 },   // Ramp down to 0 users
    ],
    thresholds: {
        http_req_duration: ['p(95)<1000'],
        http_req_failed: ['rate<0.1'],
    },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';

export default function() {
    let responses = http.batch([
        ['GET', `${BASE_URL}/api/health`],
        ['GET', `${BASE_URL}/api/orders`],
        ['GET', `${BASE_URL}/api/inventory`],
        ['GET', `${BASE_URL}/api/users`],
    ]);

    for (let i = 0; i < responses.length; i++) {
        check(responses[i], {
            'status is 200': (r) => r.status === 200,
        });
    }

    // Create order occasionally
    if (Math.random() < 0.3) {
        let orderData = {
            user_id: Math.floor(Math.random() * 5) + 1,
            product_id: Math.floor(Math.random() * 5) + 1,
            quantity: 1
        };

        let createOrderRes = http.post(`${BASE_URL}/api/orders`, JSON.stringify(orderData), {
            headers: { 'Content-Type': 'application/json' },
        });
        
        check(createOrderRes, {
            'create order successful': (r) => r.status === 201,
        });
    }

    sleep(Math.random() * 2 + 1);
}