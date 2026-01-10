import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    vus: 10,
    duration: '2m',
    thresholds: {
        http_req_duration: ['p(95)<500'],
        http_req_failed: ['rate<0.1'],
    },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';

export default function() {
    // Test health endpoint
    let healthRes = http.get(`${BASE_URL}/api/health`);
    check(healthRes, {
        'health check status is 200': (r) => r.status === 200,
    });

    // Test get orders
    let ordersRes = http.get(`${BASE_URL}/api/orders`);
    check(ordersRes, {
        'get orders status is 200': (r) => r.status === 200,
    });

    // Test get inventory
    let inventoryRes = http.get(`${BASE_URL}/api/inventory`);
    check(inventoryRes, {
        'get inventory status is 200': (r) => r.status === 200,
    });

    // Test get users
    let usersRes = http.get(`${BASE_URL}/api/users`);
    check(usersRes, {
        'get users status is 200': (r) => r.status === 200,
    });

    // Create order
    let orderData = {
        user_id: Math.floor(Math.random() * 5) + 1,
        product_id: Math.floor(Math.random() * 5) + 1,
        quantity: Math.floor(Math.random() * 3) + 1
    };

    let createOrderRes = http.post(`${BASE_URL}/api/orders`, JSON.stringify(orderData), {
        headers: { 'Content-Type': 'application/json' },
    });
    
    check(createOrderRes, {
        'create order status is 201': (r) => r.status === 201,
    });

    sleep(1);
}