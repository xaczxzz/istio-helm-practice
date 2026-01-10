#!/bin/bash
set -e

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    echo "❌ k6 is not installed. Please install k6 first:"
    echo "   macOS: brew install k6"
    echo "   Linux: https://k6.io/docs/getting-started/installation/"
    exit 1
fi

# Default values
SCENARIO="basic"
BASE_URL="http://localhost"
DURATION="2m"
VUS="10"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --scenario)
            SCENARIO="$2"
            shift 2
            ;;
        --url)
            BASE_URL="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --vus)
            VUS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --scenario SCENARIO   Load test scenario (basic|ramp-up|spike|circuit-breaker)"
            echo "  --url URL            Base URL for testing (default: http://localhost)"
            echo "  --duration DURATION  Test duration (default: 2m)"
            echo "  --vus VUS           Number of virtual users (default: 10)"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --scenario basic --vus 20 --duration 5m"
            echo "  $0 --scenario ramp-up --url http://localhost:8080"
            echo "  $0 --scenario spike"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🚀 Running k6 load test..."
echo "Scenario: $SCENARIO"
echo "Base URL: $BASE_URL"
echo "Duration: $DURATION"
echo "Virtual Users: $VUS"
echo ""

# Create temporary k6 script based on scenario
TEMP_SCRIPT="/tmp/k6-test-${SCENARIO}.js"

case $SCENARIO in
    "basic")
        cat > $TEMP_SCRIPT << EOF
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    vus: ${VUS},
    duration: '${DURATION}',
    thresholds: {
        http_req_duration: ['p(95)<500'],
        http_req_failed: ['rate<0.1'],
    },
};

export default function() {
    // Test health endpoint
    let healthRes = http.get('${BASE_URL}/api/health');
    check(healthRes, {
        'health check status is 200': (r) => r.status === 200,
    });

    // Test get orders
    let ordersRes = http.get('${BASE_URL}/api/orders');
    check(ordersRes, {
        'get orders status is 200': (r) => r.status === 200,
    });

    // Test get inventory
    let inventoryRes = http.get('${BASE_URL}/api/inventory');
    check(inventoryRes, {
        'get inventory status is 200': (r) => r.status === 200,
    });

    // Test get users
    let usersRes = http.get('${BASE_URL}/api/users');
    check(usersRes, {
        'get users status is 200': (r) => r.status === 200,
    });

    // Create order
    let orderData = {
        user_id: Math.floor(Math.random() * 5) + 1,
        product_id: Math.floor(Math.random() * 5) + 1,
        quantity: Math.floor(Math.random() * 3) + 1
    };

    let createOrderRes = http.post('${BASE_URL}/api/orders', JSON.stringify(orderData), {
        headers: { 'Content-Type': 'application/json' },
    });
    
    check(createOrderRes, {
        'create order status is 201': (r) => r.status === 201,
    });

    sleep(1);
}
EOF
        ;;
    
    "ramp-up")
        cat > $TEMP_SCRIPT << EOF
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

export default function() {
    let responses = http.batch([
        ['GET', '${BASE_URL}/api/health'],
        ['GET', '${BASE_URL}/api/orders'],
        ['GET', '${BASE_URL}/api/inventory'],
        ['GET', '${BASE_URL}/api/users'],
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

        let createOrderRes = http.post('${BASE_URL}/api/orders', JSON.stringify(orderData), {
            headers: { 'Content-Type': 'application/json' },
        });
        
        check(createOrderRes, {
            'create order successful': (r) => r.status === 201,
        });
    }

    sleep(Math.random() * 2 + 1);
}
EOF
        ;;
    
    "spike")
        cat > $TEMP_SCRIPT << EOF
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

export default function() {
    let endpoint = ['health', 'orders', 'inventory', 'users'][Math.floor(Math.random() * 4)];
    
    let res = http.get(\`${BASE_URL}/api/\${endpoint}\`);
    check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 2s': (r) => r.timings.duration < 2000,
    });

    sleep(0.5);
}
EOF
        ;;
    
    "circuit-breaker")
        cat > $TEMP_SCRIPT << EOF
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    vus: 30,
    duration: '${DURATION}',
    thresholds: {
        http_req_duration: ['p(95)<3000'],
        // Allow higher error rate for circuit breaker testing
        http_req_failed: ['rate<0.5'],
    },
};

export default function() {
    // Aggressive load to trigger circuit breaker
    let responses = http.batch([
        ['GET', '${BASE_URL}/api/orders'],
        ['GET', '${BASE_URL}/api/inventory'],
        ['GET', '${BASE_URL}/api/users'],
        ['GET', '${BASE_URL}/api/orders'],
        ['GET', '${BASE_URL}/api/inventory'],
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

        http.post('${BASE_URL}/api/orders', JSON.stringify(orderData), {
            headers: { 'Content-Type': 'application/json' },
        });
    }

    sleep(0.1); // Very short sleep for aggressive load
}
EOF
        ;;
    
    *)
        echo "❌ Unknown scenario: $SCENARIO"
        echo "Available scenarios: basic, ramp-up, spike, circuit-breaker"
        exit 1
        ;;
esac

# Check if the application is accessible
echo "🔍 Checking application accessibility..."
if ! curl -f -s "${BASE_URL}/api/health" > /dev/null; then
    echo "❌ Application is not accessible at ${BASE_URL}"
    echo "Make sure the application is running and accessible."
    echo ""
    echo "To set up port forwarding:"
    echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
    echo "  Then use: $0 --url http://localhost:8080"
    exit 1
fi

echo "✅ Application is accessible"
echo ""

# Run the load test
echo "🏃 Starting load test..."
k6 run $TEMP_SCRIPT

# Clean up
rm -f $TEMP_SCRIPT

echo ""
echo "🎉 Load test completed!"
echo ""
echo "📊 Check the results in:"
echo "  - Grafana dashboards: ${BASE_URL}/grafana"
echo "  - Kiali service mesh: ${BASE_URL}/kiali"
echo "  - Jaeger tracing: ${BASE_URL}/jaeger"
echo ""
echo "💡 Tips:"
echo "  - Run different scenarios to see various load patterns"
echo "  - Monitor the applications in Grafana during the test"
echo "  - Check Kiali for service mesh traffic visualization"
echo "  - Use Jaeger to trace individual requests"