package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/jaeger"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
)

var (
	Version = "v1.0.0" // Can be overridden at build time
	db      *sql.DB
	
	// Prometheus metrics
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "order_service_requests_total",
			Help: "Total number of requests",
		},
		[]string{"method", "endpoint", "status_code"},
	)
	
	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "order_service_request_duration_seconds",
			Help: "Request duration in seconds",
		},
		[]string{"method", "endpoint"},
	)
	
	ordersCreated = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "order_service_orders_created_total",
			Help: "Total number of orders created",
		},
	)
)

type Order struct {
	ID        int       `json:"id" db:"id"`
	UserID    int       `json:"user_id" db:"user_id"`
	ProductID int       `json:"product_id" db:"product_id"`
	Quantity  int       `json:"quantity" db:"quantity"`
	Status    string    `json:"status" db:"status"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type CreateOrderRequest struct {
	UserID    int `json:"user_id" binding:"required"`
	ProductID int `json:"product_id" binding:"required"`
	Quantity  int `json:"quantity" binding:"required,min=1"`
}

func init() {
	// Register Prometheus metrics
	prometheus.MustRegister(requestsTotal)
	prometheus.MustRegister(requestDuration)
	prometheus.MustRegister(ordersCreated)
}

func initTracing() func() {
	// Create Jaeger exporter
	exp, err := jaeger.New(jaeger.WithCollectorEndpoint(jaeger.WithEndpoint(
		fmt.Sprintf("http://%s:14268/api/traces", 
			getEnv("JAEGER_ENDPOINT", "jaeger")),
	)))
	if err != nil {
		log.Printf("Failed to create Jaeger exporter: %v", err)
		return func() {}
	}

	// Create trace provider
	tp := trace.NewTracerProvider(
		trace.WithBatcher(exp),
		trace.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName("order-service"),
			semconv.ServiceVersion(Version),
		)),
	)

	otel.SetTracerProvider(tp)

	return func() {
		if err := tp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}
}

func initDB() {
	dbHost := getEnv("DB_HOST", "postgresql")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "postgres")
	dbPassword := getEnv("DB_PASSWORD", "postgres")
	dbName := getEnv("DB_NAME", "postgres")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPassword, dbName)

	var err error
	
	// Retry logic for database connection
	maxRetries := 30
	retryDelay := 2 * time.Second
	
	for i := 0; i < maxRetries; i++ {
		db, err = sql.Open("postgres", connStr)
		if err != nil {
			log.Printf("Attempt %d/%d: Failed to open database connection: %v", i+1, maxRetries, err)
			time.Sleep(retryDelay)
			continue
		}

		// Set connection pool settings
		db.SetMaxOpenConns(25)
		db.SetMaxIdleConns(5)
		db.SetConnMaxLifetime(5 * time.Minute)

		// Test connection
		err = db.Ping()
		if err == nil {
			log.Println("Database connection established successfully")
			break
		}
		
		log.Printf("Attempt %d/%d: Failed to ping database: %v", i+1, maxRetries, err)
		db.Close()
		time.Sleep(retryDelay)
	}
	
	if err != nil {
		log.Fatal("Failed to connect to database after retries:", err)
	}

	// Create orders table if not exists
	createTableQuery := `
	CREATE TABLE IF NOT EXISTS orders (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL,
		product_id INTEGER NOT NULL,
		quantity INTEGER NOT NULL,
		status VARCHAR(50) DEFAULT 'pending',
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	)`

	if _, err = db.Exec(createTableQuery); err != nil {
		log.Fatal("Failed to create orders table:", err)
	}

	log.Println("Database initialized successfully")
}

func prometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		
		c.Next()
		
		duration := time.Since(start).Seconds()
		statusCode := strconv.Itoa(c.Writer.Status())
		
		requestsTotal.WithLabelValues(c.Request.Method, c.FullPath(), statusCode).Inc()
		requestDuration.WithLabelValues(c.Request.Method, c.FullPath()).Observe(duration)
	}
}

func podInfoMiddleware() gin.HandlerFunc {
	hostname, _ := os.Hostname()
	return func(c *gin.Context) {
		c.Header("X-Pod-Name", hostname)
		c.Header("X-Service-Version", Version)
		c.Next()
	}
}

func healthHandler(c *gin.Context) {
	hostname, _ := os.Hostname()
	
	// Check database connection
	dbStatus := "healthy"
	if err := db.Ping(); err != nil {
		dbStatus = "unhealthy"
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":    "unhealthy",
			"service":   "order-service",
			"version":   Version,
			"pod_name":  hostname,
			"database":  dbStatus,
			"timestamp": time.Now().Unix(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":    "healthy",
		"service":   "order-service",
		"version":   Version,
		"pod_name":  hostname,
		"database":  dbStatus,
		"timestamp": time.Now().Unix(),
	})
}

func getOrdersHandler(c *gin.Context) {
	ctx, span := otel.Tracer("order-service").Start(c.Request.Context(), "get_orders")
	defer span.End()

	rows, err := db.QueryContext(ctx, "SELECT id, user_id, product_id, quantity, status, created_at FROM orders ORDER BY created_at DESC LIMIT 100")
	if err != nil {
		log.Printf("Failed to query orders: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch orders"})
		return
	}
	defer rows.Close()

	var orders []Order
	for rows.Next() {
		var order Order
		err := rows.Scan(&order.ID, &order.UserID, &order.ProductID, &order.Quantity, &order.Status, &order.CreatedAt)
		if err != nil {
			log.Printf("Failed to scan order: %v", err)
			continue
		}
		orders = append(orders, order)
	}

	hostname, _ := os.Hostname()
	c.JSON(http.StatusOK, gin.H{
		"orders":   orders,
		"count":    len(orders),
		"pod_name": hostname,
		"version":  Version,
	})
}

func createOrderHandler(c *gin.Context) {
	ctx, span := otel.Tracer("order-service").Start(c.Request.Context(), "create_order")
	defer span.End()

	var req CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Simulate some processing time
	time.Sleep(time.Duration(50+rand.Intn(100)) * time.Millisecond)

	var orderID int
	err := db.QueryRowContext(ctx,
		"INSERT INTO orders (user_id, product_id, quantity, status) VALUES ($1, $2, $3, 'pending') RETURNING id",
		req.UserID, req.ProductID, req.Quantity).Scan(&orderID)
	
	if err != nil {
		log.Printf("Failed to create order: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create order"})
		return
	}

	// Increment orders created metric
	ordersCreated.Inc()

	// Simulate calling inventory service
	go func() {
		// This would normally call the inventory service
		time.Sleep(100 * time.Millisecond)
		log.Printf("Order %d: Inventory check completed", orderID)
	}()

	hostname, _ := os.Hostname()
	order := Order{
		ID:        orderID,
		UserID:    req.UserID,
		ProductID: req.ProductID,
		Quantity:  req.Quantity,
		Status:    "pending",
		CreatedAt: time.Now(),
	}

	c.JSON(http.StatusCreated, gin.H{
		"order":    order,
		"message":  "Order created successfully",
		"pod_name": hostname,
		"version":  Version,
	})
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	// Initialize tracing
	cleanup := initTracing()
	defer cleanup()

	// Initialize database
	initDB()
	defer db.Close()

	// Set Gin mode
	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Create Gin router
	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())
	r.Use(otelgin.Middleware("order-service"))
	r.Use(prometheusMiddleware())
	r.Use(podInfoMiddleware())

	// Routes
	r.GET("/health", healthHandler)
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))
	r.GET("/orders", getOrdersHandler)
	r.POST("/orders", createOrderHandler)

	// Start server
	port := getEnv("PORT", "8080")
	log.Printf("Order Service %s starting on port %s", Version, port)
	
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}