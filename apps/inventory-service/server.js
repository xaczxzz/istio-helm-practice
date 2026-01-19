const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { Pool } = require('pg');
const client = require('prom-client');
const os = require('os');

// Initialize OpenTelemetry
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { JaegerExporter } = require('@opentelemetry/exporter-jaeger');

const jaegerExporter = new JaegerExporter({
  endpoint: `http://${process.env.JAEGER_ENDPOINT || 'jaeger'}:14268/api/traces`,
});

const sdk = new NodeSDK({
  traceExporter: jaegerExporter,
  instrumentations: [getNodeAutoInstrumentations()],
  serviceName: 'inventory-service',
  serviceVersion: process.env.SERVICE_VERSION || 'v1.0.0',
});

sdk.start();

const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.SERVICE_VERSION || 'v1.0.0';

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'inventory_service_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'inventory_service_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route'],
  registers: [register],
});

const inventoryItemsTotal = new client.Gauge({
  name: 'inventory_service_items_total',
  help: 'Total number of inventory items',
  registers: [register],
});

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST || 'postgresql',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'postgres',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  max: 15,                    // 20 → 15로 줄임
  min: 2,                     // 최소 연결 수 추가
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,  // 5초 → 10초로 증가
  acquireTimeoutMillis: 60000,     // 연결 획득 타임아웃 추가
  createTimeoutMillis: 30000,      // 연결 생성 타임아웃 추가
  destroyTimeoutMillis: 5000,      // 연결 해제 타임아웃 추가
  reapIntervalMillis: 1000,        // 유휴 연결 정리 간격
  createRetryIntervalMillis: 200,  // 연결 재시도 간격
});

// Initialize database with retry logic
async function initDB() {
  const maxRetries = 30;
  const retryDelay = 2000; // 2 seconds
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const client = await pool.connect();
      
      // Create inventory table if not exists
      await client.query(`
        CREATE TABLE IF NOT EXISTS inventory (
          id SERIAL PRIMARY KEY,
          product_id INTEGER UNIQUE NOT NULL,
          product_name VARCHAR(255) NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 0,
          price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Insert sample data if table is empty
      const result = await client.query('SELECT COUNT(*) FROM inventory');
      if (parseInt(result.rows[0].count) === 0) {
        const sampleData = [
          [1, 'Laptop', 50, 999.99],
          [2, 'Mouse', 200, 29.99],
          [3, 'Keyboard', 150, 79.99],
          [4, 'Monitor', 75, 299.99],
          [5, 'Headphones', 100, 149.99],
        ];

        for (const [id, name, qty, price] of sampleData) {
          await client.query(
            'INSERT INTO inventory (product_id, product_name, quantity, price) VALUES ($1, $2, $3, $4)',
            [id, name, qty, price]
          );
        }
        console.log('Sample inventory data inserted');
      }

      client.release();
      console.log(`Database initialized successfully (attempt ${attempt})`);
      return;
    } catch (err) {
      console.error(`Attempt ${attempt}/${maxRetries}: Database initialization failed:`, err.message);
      if (attempt < maxRetries) {
        console.log(`Retrying in ${retryDelay / 1000} seconds...`);
        await new Promise(resolve => setTimeout(resolve, retryDelay));
      } else {
        console.error('Failed to initialize database after all retries');
        process.exit(1);
      }
    }
  }
}

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Prometheus middleware
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    
    httpRequestsTotal
      .labels(req.method, route, res.statusCode.toString())
      .inc();
    
    httpRequestDuration
      .labels(req.method, route)
      .observe(duration);
  });
  
  next();
});

// Pod info middleware
app.use((req, res, next) => {
  res.set({
    'X-Pod-Name': os.hostname(),
    'X-Service-Version': VERSION,
  });
  next();
});

// Routes
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    
    res.json({
      status: 'healthy',
      service: 'inventory-service',
      version: VERSION,
      pod_name: os.hostname(),
      database: 'healthy',
      timestamp: Math.floor(Date.now() / 1000),
    });
  } catch (err) {
    console.error('Health check failed:', err);
    res.status(503).json({
      status: 'unhealthy',
      service: 'inventory-service',
      version: VERSION,
      pod_name: os.hostname(),
      database: 'unhealthy',
      error: err.message,
      timestamp: Math.floor(Date.now() / 1000),
    });
  }
});

app.get('/metrics', (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});

app.get('/inventory', async (req, res) => {
  try {
    // Simulate some processing time
    await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 100));
    
    const client = await pool.connect();
    const result = await client.query(
      'SELECT product_id, product_name, quantity, price, updated_at FROM inventory ORDER BY product_id'
    );
    client.release();
    
    // Update metrics
    inventoryItemsTotal.set(result.rows.length);
    
    res.json({
      inventory: result.rows,
      count: result.rows.length,
      pod_name: os.hostname(),
      version: VERSION,
    });
  } catch (err) {
    console.error('Failed to fetch inventory:', err);
    res.status(500).json({
      error: 'Failed to fetch inventory',
      message: err.message,
    });
  }
});

app.get('/inventory/:productId', async (req, res) => {
  try {
    const productId = parseInt(req.params.productId);
    
    if (isNaN(productId)) {
      return res.status(400).json({ error: 'Invalid product ID' });
    }
    
    const client = await pool.connect();
    const result = await client.query(
      'SELECT product_id, product_name, quantity, price, updated_at FROM inventory WHERE product_id = $1',
      [productId]
    );
    client.release();
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    res.json({
      product: result.rows[0],
      pod_name: os.hostname(),
      version: VERSION,
    });
  } catch (err) {
    console.error('Failed to fetch product:', err);
    res.status(500).json({
      error: 'Failed to fetch product',
      message: err.message,
    });
  }
});

app.put('/inventory/:productId', async (req, res) => {
  try {
    const productId = parseInt(req.params.productId);
    const { quantity } = req.body;
    
    if (isNaN(productId) || typeof quantity !== 'number' || quantity < 0) {
      return res.status(400).json({ error: 'Invalid input' });
    }
    
    const client = await pool.connect();
    const result = await client.query(
      'UPDATE inventory SET quantity = $1, updated_at = CURRENT_TIMESTAMP WHERE product_id = $2 RETURNING *',
      [quantity, productId]
    );
    client.release();
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    res.json({
      message: 'Inventory updated successfully',
      product: result.rows[0],
      pod_name: os.hostname(),
      version: VERSION,
    });
  } catch (err) {
    console.error('Failed to update inventory:', err);
    res.status(500).json({
      error: 'Failed to update inventory',
      message: err.message,
    });
  }
});

// Check inventory for order (called by order service)
app.post('/inventory/check', async (req, res) => {
  try {
    const { product_id, quantity } = req.body;
    
    if (!product_id || !quantity || quantity <= 0) {
      return res.status(400).json({ error: 'Invalid request' });
    }
    
    const client = await pool.connect();
    const result = await client.query(
      'SELECT product_id, product_name, quantity FROM inventory WHERE product_id = $1',
      [product_id]
    );
    client.release();
    
    if (result.rows.length === 0) {
      return res.status(404).json({ 
        available: false,
        error: 'Product not found' 
      });
    }
    
    const product = result.rows[0];
    const available = product.quantity >= quantity;
    
    res.json({
      available,
      product_id: product.product_id,
      product_name: product.product_name,
      requested_quantity: quantity,
      available_quantity: product.quantity,
      pod_name: os.hostname(),
      version: VERSION,
    });
  } catch (err) {
    console.error('Failed to check inventory:', err);
    res.status(500).json({
      error: 'Failed to check inventory',
      message: err.message,
    });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: err.message,
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path,
  });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  await pool.end();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, shutting down gracefully');
  await pool.end();
  process.exit(0);
});

// Start server
async function start() {
  try {
    await initDB();
    
    app.listen(PORT, () => {
      console.log(`Inventory Service ${VERSION} listening on port ${PORT}`);
      console.log(`Pod: ${os.hostname()}`);
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();