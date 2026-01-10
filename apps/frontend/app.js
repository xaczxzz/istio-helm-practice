// Global variables
let requestCount = 0;
let successCount = 0;
let errorCount = 0;
let totalResponseTime = 0;
let currentPod = '';

// Initialize the application
document.addEventListener('DOMContentLoaded', function() {
    console.log('K8s 3-Tier Observability Lab initialized');
    
    // Start periodic health checks
    setInterval(checkServiceHealth, 5000);
    setInterval(updateMetrics, 1000);
    
    // Initial health check
    checkServiceHealth();
});

// Test API endpoints
async function testAPI(endpoint) {
    const startTime = Date.now();
    const logContainer = document.getElementById('response-log');
    
    try {
        addLogEntry(`🔄 Testing ${endpoint}...`, 'info');
        
        const response = await fetch(endpoint, {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json',
            }
        });
        
        const endTime = Date.now();
        const responseTime = endTime - startTime;
        
        // Update metrics
        requestCount++;
        totalResponseTime += responseTime;
        
        if (response.ok) {
            successCount++;
            const data = await response.json();
            
            // Extract pod information from headers
            const podName = response.headers.get('X-Pod-Name') || 'unknown';
            currentPod = podName;
            document.getElementById('current-pod').textContent = podName;
            
            addLogEntry(`✅ ${endpoint} - ${response.status} (${responseTime}ms) - Pod: ${podName}`, 'success');
            addLogEntry(`📄 Response: ${JSON.stringify(data, null, 2)}`, 'data');
        } else {
            errorCount++;
            addLogEntry(`❌ ${endpoint} - ${response.status} (${responseTime}ms)`, 'error');
        }
        
    } catch (error) {
        const endTime = Date.now();
        const responseTime = endTime - startTime;
        
        requestCount++;
        errorCount++;
        totalResponseTime += responseTime;
        
        addLogEntry(`💥 ${endpoint} - Network Error (${responseTime}ms): ${error.message}`, 'error');
    }
}

// Create a new order
async function createOrder() {
    const orderData = {
        user_id: Math.floor(Math.random() * 100) + 1,
        product_id: Math.floor(Math.random() * 50) + 1,
        quantity: Math.floor(Math.random() * 5) + 1
    };
    
    const startTime = Date.now();
    
    try {
        addLogEntry(`🛒 Creating order: ${JSON.stringify(orderData)}`, 'info');
        
        const response = await fetch('/api/orders', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(orderData)
        });
        
        const endTime = Date.now();
        const responseTime = endTime - startTime;
        
        requestCount++;
        totalResponseTime += responseTime;
        
        if (response.ok) {
            successCount++;
            const data = await response.json();
            const podName = response.headers.get('X-Pod-Name') || 'unknown';
            currentPod = podName;
            document.getElementById('current-pod').textContent = podName;
            
            addLogEntry(`✅ Order created - ${response.status} (${responseTime}ms) - Pod: ${podName}`, 'success');
            addLogEntry(`📄 Order: ${JSON.stringify(data, null, 2)}`, 'data');
        } else {
            errorCount++;
            addLogEntry(`❌ Order creation failed - ${response.status} (${responseTime}ms)`, 'error');
        }
        
    } catch (error) {
        const endTime = Date.now();
        const responseTime = endTime - startTime;
        
        requestCount++;
        errorCount++;
        totalResponseTime += responseTime;
        
        addLogEntry(`💥 Order creation error (${responseTime}ms): ${error.message}`, 'error');
    }
}

// Check service health
async function checkServiceHealth() {
    const services = [
        { name: 'frontend', endpoint: '/health', indicator: 'frontend-indicator' },
        { name: 'api-gateway', endpoint: '/api/health', indicator: 'api-gateway-indicator' },
        { name: 'order', endpoint: '/api/orders/health', indicator: 'order-indicator' },
        { name: 'inventory', endpoint: '/api/inventory/health', indicator: 'inventory-indicator' },
        { name: 'user', endpoint: '/api/users/health', indicator: 'user-indicator' }
    ];
    
    for (const service of services) {
        try {
            const response = await fetch(service.endpoint, { 
                method: 'GET',
                timeout: 3000 
            });
            
            const indicator = document.getElementById(service.indicator);
            if (response.ok) {
                indicator.className = 'status-indicator healthy';
                indicator.textContent = '●';
            } else {
                indicator.className = 'status-indicator warning';
                indicator.textContent = '●';
            }
        } catch (error) {
            const indicator = document.getElementById(service.indicator);
            indicator.className = 'status-indicator error';
            indicator.textContent = '●';
        }
    }
}

// Update real-time metrics
function updateMetrics() {
    if (requestCount > 0) {
        const avgResponseTime = Math.round(totalResponseTime / requestCount);
        const successRate = Math.round((successCount / requestCount) * 100);
        const errorRate = Math.round((errorCount / requestCount) * 100);
        
        document.getElementById('response-time').textContent = `${avgResponseTime}ms`;
        document.getElementById('success-rate').textContent = `${successRate}%`;
        document.getElementById('error-rate').textContent = `${errorRate}%`;
    }
    
    // Calculate RPS (requests in last 60 seconds)
    const rps = Math.round(requestCount / 60);
    document.getElementById('rps').textContent = rps;
}

// Add log entry
function addLogEntry(message, type = 'info') {
    const logContainer = document.getElementById('response-log');
    const timestamp = new Date().toLocaleTimeString();
    
    const logEntry = document.createElement('p');
    logEntry.className = `log-entry log-${type}`;
    logEntry.innerHTML = `<span class="timestamp">[${timestamp}]</span> ${message}`;
    
    logContainer.appendChild(logEntry);
    logContainer.scrollTop = logContainer.scrollHeight;
    
    // Keep only last 50 entries
    const entries = logContainer.querySelectorAll('.log-entry');
    if (entries.length > 50) {
        entries[0].remove();
    }
}

// Clear log
function clearLog() {
    const logContainer = document.getElementById('response-log');
    logContainer.innerHTML = '<p class="log-entry">Log cleared...</p>';
    
    // Reset metrics
    requestCount = 0;
    successCount = 0;
    errorCount = 0;
    totalResponseTime = 0;
    
    document.getElementById('response-time').textContent = '-';
    document.getElementById('success-rate').textContent = '-';
    document.getElementById('error-rate').textContent = '-';
    document.getElementById('rps').textContent = '-';
}

// Utility function for timeout
function fetchWithTimeout(url, options = {}, timeout = 5000) {
    return Promise.race([
        fetch(url, options),
        new Promise((_, reject) =>
            setTimeout(() => reject(new Error('Request timeout')), timeout)
        )
    ]);
}