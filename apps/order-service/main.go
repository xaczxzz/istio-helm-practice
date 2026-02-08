package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
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

// Response structures for external services
type InventoryCheckResponse struct {
	Available         bool   `json:"available"`
	ProductID         int    `json:"product_id"`
	ProductName       string `json:"product_name"`
	RequestedQuantity int    `json:"requested_quantity"`
	AvailableQuantity int    `json:"available_quantity"`
}

type UserInfoResponse struct {
	User struct {
		ID       int    `json:"id"`
		Username string `json:"username"`
		Email    string `json:"email"`
		FullName string `json:"full_name"`
	} `json:"user"`
}

func init() {
	// Register Prometheus metrics
	prometheus.MustRegister(requestsTotal)
	prometheus.MustRegister(requestDuration)
	prometheus.MustRegister(ordersCreated)
}

func initTracing() func() {
	// Check if Jaeger is enabled
	jaegerEnabled := getEnv("JAEGER_ENABLED", "false")
	if jaegerEnabled != "true" {
		log.Println("Jaeger tracing disabled")
		return func() {}
	}

	// Create Jaeger exporter
	exp, err := jaeger.New(jaeger.WithCollectorEndpoint(jaeger.WithEndpoint(
		fmt.Sprintf("http://%s:14268/api/traces", 
			getEnv("JAEGER_ENDPOINT", "jaeger")),
	)))
	if err != nil {
		log.Printf("Failed to create Jaeger exporter: %v", err)
		return func() {}
	}

	log.Println("Jaeger tracing enabled")

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
		db.SetMaxOpenConns(15)           // 25 → 15로 줄임
		db.SetMaxIdleConns(3)            // 5 → 3으로 줄임
		db.SetConnMaxLifetime(5 * time.Minute)
		db.SetConnMaxIdleTime(30 * time.Second)  // 유휴 연결 타임아웃 추가

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

	// Use context with timeout for table creation
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	
	if _, err = db.ExecContext(ctx, createTableQuery); err != nil {
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
	
	// Check database connection with timeout
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	
	dbStatus := "healthy"
	if err := db.PingContext(ctx); err != nil {
		dbStatus = "unhealthy"
		log.Printf("Health check DB ping failed: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":    "unhealthy",
			"service":   "order-service",
			"version":   Version,
			"pod_name":  hostname,
			"database":  dbStatus,
			"error":     err.Error(),
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

	// Step 1: Check inventory availability
	log.Printf("Checking inventory for product %d, quantity %d", req.ProductID, req.Quantity)
	inventoryAvailable, inventoryInfo, err := checkInventory(ctx, req.ProductID, req.Quantity)
	if err != nil {
		log.Printf("Failed to check inventory: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "Failed to check inventory",
			"details": err.Error(),
		})
		return
	}

	if !inventoryAvailable {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":              "Insufficient inventory",
			"product_id":         req.ProductID,
			"requested_quantity": req.Quantity,
			"available_quantity": inventoryInfo.AvailableQuantity,
		})
		return
	}

	// Step 2: Get user information
	log.Printf("Fetching user information for user %d", req.UserID)
	userInfo, err := getUserInfo(ctx, req.UserID)
	if err != nil {
		log.Printf("Failed to get user info: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "Failed to get user information",
			"details": err.Error(),
		})
		return
	}

	// Step 3: Create order in database
	var orderID int
	err = db.QueryRowContext(ctx,
		"INSERT INTO orders (user_id, product_id, quantity, status) VALUES ($1, $2, $3, 'confirmed') RETURNING id",
		req.UserID, req.ProductID, req.Quantity).Scan(&orderID)
	
	if err != nil {
		log.Printf("Failed to create order: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create order"})
		return
	}

	// Increment orders created metric
	ordersCreated.Inc()

	hostname, _ := os.Hostname()
	order := Order{
		ID:        orderID,
		UserID:    req.UserID,
		ProductID: req.ProductID,
		Quantity:  req.Quantity,
		Status:    "confirmed",
		CreatedAt: time.Now(),
	}

	c.JSON(http.StatusCreated, gin.H{
		"order":    order,
		"message":  "Order created successfully with inventory and user validation",
		"pod_name": hostname,
		"version":  Version,
		"inventory_check": gin.H{
			"product_name":       inventoryInfo.ProductName,
			"available_quantity": inventoryInfo.AvailableQuantity,
		},
		"user_info": gin.H{
			"username": userInfo.User.Username,
			"email":    userInfo.User.Email,
			"fullname": userInfo.User.FullName,
		},
	})
}

// checkInventory calls inventory service to check product availability
func checkInventory(ctx context.Context, productID, quantity int) (bool, *InventoryCheckResponse, error) {
	inventoryServiceURL := getEnv("INVENTORY_SERVICE_URL", "http://app-stack-inventory-service:3000")
	url := fmt.Sprintf("%s/inventory/check", inventoryServiceURL)

	reqBody := map[string]int{
		"product_id": productID,
		"quantity":   quantity,
	}
	jsonData, _ := json.Marshal(reqBody)

	req, err := http.NewRequestWithContext(ctx, "POST", url, nil)
	if err != nil {
		return false, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Body = io.NopCloser(bytes.NewBuffer(jsonData))

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false, nil, fmt.Errorf("inventory service unreachable: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, nil, fmt.Errorf("inventory service returned status %d", resp.StatusCode)
	}

	var inventoryResp InventoryCheckResponse
	if err := json.NewDecoder(resp.Body).Decode(&inventoryResp); err != nil {
		return false, nil, err
	}

	return inventoryResp.Available, &inventoryResp, nil
}

// getUserInfo calls user service to get user information
func getUserInfo(ctx context.Context, userID int) (*UserInfoResponse, error) {
	userServiceURL := getEnv("USER_SERVICE_URL", "http://app-stack-user-service:8000")
	url := fmt.Sprintf("%s/users/%d", userServiceURL, userID)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("user service unreachable: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("user not found")
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("user service returned status %d", resp.StatusCode)
	}

	var userResp UserInfoResponse
	if err := json.NewDecoder(resp.Body).Decode(&userResp); err != nil {
		return nil, err
	}

	return &userResp, nil
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