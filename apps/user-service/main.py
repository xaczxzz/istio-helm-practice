import os
import time
import socket
import logging
import psycopg2
from typing import List, Optional
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize OpenTelemetry
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

# Configure Jaeger exporter
jaeger_exporter = JaegerExporter(
    agent_host_name=os.getenv("JAEGER_AGENT_HOST", "jaeger"),
    agent_port=int(os.getenv("JAEGER_AGENT_PORT", "6831")),
)

span_processor = BatchSpanProcessor(jaeger_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Instrument psycopg2
Psycopg2Instrumentor().instrument()

# Database connection
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "postgresql"),
    "port": os.getenv("DB_PORT", "5432"),
    "database": os.getenv("DB_NAME", "postgres"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
}

# Global database connection
db_connection = None

def get_db_connection():
    global db_connection
    max_retries = 30
    retry_delay = 2
    
    if db_connection is None or db_connection.closed:
        for attempt in range(max_retries):
            try:
                db_connection = psycopg2.connect(**DB_CONFIG)
                logger.info(f"Database connection established (attempt {attempt + 1})")
                return db_connection
            except psycopg2.OperationalError as e:
                if attempt < max_retries - 1:
                    logger.warning(f"Attempt {attempt + 1}/{max_retries}: Failed to connect to database: {e}")
                    time.sleep(retry_delay)
                else:
                    logger.error(f"Failed to connect to database after {max_retries} attempts")
                    raise
    return db_connection

async def init_db():
    """Initialize database and create tables"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Create users table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                username VARCHAR(100) UNIQUE NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                full_name VARCHAR(255) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Check if table is empty and insert sample data
        cursor.execute("SELECT COUNT(*) FROM users")
        count = cursor.fetchone()[0]
        
        if count == 0:
            sample_users = [
                ("john_doe", "john@example.com", "John Doe"),
                ("jane_smith", "jane@example.com", "Jane Smith"),
                ("bob_wilson", "bob@example.com", "Bob Wilson"),
                ("alice_brown", "alice@example.com", "Alice Brown"),
                ("charlie_davis", "charlie@example.com", "Charlie Davis"),
            ]
            
            for username, email, full_name in sample_users:
                cursor.execute(
                    "INSERT INTO users (username, email, full_name) VALUES (%s, %s, %s)",
                    (username, email, full_name)
                )
            
            logger.info("Sample user data inserted")
        
        conn.commit()
        cursor.close()
        logger.info("Database initialized successfully")
        
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        raise

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await init_db()
    yield
    # Shutdown
    if db_connection and not db_connection.closed:
        db_connection.close()

# Initialize FastAPI
app = FastAPI(
    title="User Service",
    description="User Service for K8s 3-Tier Observability Lab",
    version=os.getenv("SERVICE_VERSION", "1.0.0"),
    lifespan=lifespan
)

# Instrument FastAPI
FastAPIInstrumentor.instrument_app(app)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics
REQUEST_COUNT = Counter(
    'user_service_requests_total',
    'Total number of requests',
    ['method', 'endpoint', 'status_code']
)

REQUEST_DURATION = Histogram(
    'user_service_request_duration_seconds',
    'Request duration in seconds',
    ['method', 'endpoint']
)

USERS_TOTAL = Counter(
    'user_service_users_total',
    'Total number of users created'
)

# Get pod information
POD_NAME = os.getenv("HOSTNAME", socket.gethostname())
POD_IP = socket.gethostbyname(socket.gethostname())
VERSION = os.getenv("SERVICE_VERSION", "1.0.0")

# Pydantic models
class User(BaseModel):
    id: int
    username: str
    email: str
    full_name: str
    created_at: str
    updated_at: str

class CreateUserRequest(BaseModel):
    username: str
    email: str
    full_name: str

class UpdateUserRequest(BaseModel):
    email: Optional[str] = None
    full_name: Optional[str] = None

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    response.headers["X-Pod-Name"] = POD_NAME
    response.headers["X-Pod-IP"] = POD_IP
    response.headers["X-Service-Version"] = VERSION
    
    # Record metrics
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status_code=response.status_code
    ).inc()
    
    REQUEST_DURATION.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(process_time)
    
    return response

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check database connection
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        
        return {
            "status": "healthy",
            "service": "user-service",
            "version": VERSION,
            "pod_name": POD_NAME,
            "pod_ip": POD_IP,
            "database": "healthy",
            "timestamp": time.time()
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(
            status_code=503,
            detail={
                "status": "unhealthy",
                "service": "user-service",
                "version": VERSION,
                "pod_name": POD_NAME,
                "database": "unhealthy",
                "error": str(e),
                "timestamp": time.time()
            }
        )

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/users", response_model=dict)
async def get_users():
    """Get all users"""
    with tracer.start_as_current_span("get_users") as span:
        try:
            # Simulate some processing time
            time.sleep(0.05 + (time.time() % 0.1))
            
            conn = get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, username, email, full_name, 
                       created_at::text, updated_at::text 
                FROM users 
                ORDER BY created_at DESC
            """)
            
            rows = cursor.fetchall()
            cursor.close()
            
            users = []
            for row in rows:
                users.append({
                    "id": row[0],
                    "username": row[1],
                    "email": row[2],
                    "full_name": row[3],
                    "created_at": row[4],
                    "updated_at": row[5]
                })
            
            span.set_attribute("user_count", len(users))
            
            return {
                "users": users,
                "count": len(users),
                "pod_name": POD_NAME,
                "version": VERSION
            }
            
        except Exception as e:
            logger.error(f"Failed to fetch users: {e}")
            raise HTTPException(status_code=500, detail="Failed to fetch users")

@app.get("/users/{user_id}", response_model=dict)
async def get_user(user_id: int):
    """Get user by ID"""
    with tracer.start_as_current_span("get_user") as span:
        span.set_attribute("user_id", user_id)
        
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, username, email, full_name, 
                       created_at::text, updated_at::text 
                FROM users 
                WHERE id = %s
            """, (user_id,))
            
            row = cursor.fetchone()
            cursor.close()
            
            if not row:
                raise HTTPException(status_code=404, detail="User not found")
            
            user = {
                "id": row[0],
                "username": row[1],
                "email": row[2],
                "full_name": row[3],
                "created_at": row[4],
                "updated_at": row[5]
            }
            
            return {
                "user": user,
                "pod_name": POD_NAME,
                "version": VERSION
            }
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Failed to fetch user {user_id}: {e}")
            raise HTTPException(status_code=500, detail="Failed to fetch user")

@app.post("/users", response_model=dict)
async def create_user(user_data: CreateUserRequest):
    """Create a new user"""
    with tracer.start_as_current_span("create_user") as span:
        span.set_attribute("username", user_data.username)
        
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO users (username, email, full_name) 
                VALUES (%s, %s, %s) 
                RETURNING id, username, email, full_name, 
                          created_at::text, updated_at::text
            """, (user_data.username, user_data.email, user_data.full_name))
            
            row = cursor.fetchone()
            conn.commit()
            cursor.close()
            
            # Increment users created metric
            USERS_TOTAL.inc()
            
            user = {
                "id": row[0],
                "username": row[1],
                "email": row[2],
                "full_name": row[3],
                "created_at": row[4],
                "updated_at": row[5]
            }
            
            return {
                "message": "User created successfully",
                "user": user,
                "pod_name": POD_NAME,
                "version": VERSION
            }
            
        except psycopg2.IntegrityError as e:
            conn.rollback()
            if "username" in str(e):
                raise HTTPException(status_code=400, detail="Username already exists")
            elif "email" in str(e):
                raise HTTPException(status_code=400, detail="Email already exists")
            else:
                raise HTTPException(status_code=400, detail="User creation failed")
        except Exception as e:
            logger.error(f"Failed to create user: {e}")
            raise HTTPException(status_code=500, detail="Failed to create user")

@app.put("/users/{user_id}", response_model=dict)
async def update_user(user_id: int, user_data: UpdateUserRequest):
    """Update user"""
    with tracer.start_as_current_span("update_user") as span:
        span.set_attribute("user_id", user_id)
        
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            
            # Build dynamic update query
            update_fields = []
            values = []
            
            if user_data.email is not None:
                update_fields.append("email = %s")
                values.append(user_data.email)
            
            if user_data.full_name is not None:
                update_fields.append("full_name = %s")
                values.append(user_data.full_name)
            
            if not update_fields:
                raise HTTPException(status_code=400, detail="No fields to update")
            
            update_fields.append("updated_at = CURRENT_TIMESTAMP")
            values.append(user_id)
            
            query = f"""
                UPDATE users 
                SET {', '.join(update_fields)}
                WHERE id = %s
                RETURNING id, username, email, full_name, 
                          created_at::text, updated_at::text
            """
            
            cursor.execute(query, values)
            row = cursor.fetchone()
            
            if not row:
                raise HTTPException(status_code=404, detail="User not found")
            
            conn.commit()
            cursor.close()
            
            user = {
                "id": row[0],
                "username": row[1],
                "email": row[2],
                "full_name": row[3],
                "created_at": row[4],
                "updated_at": row[5]
            }
            
            return {
                "message": "User updated successfully",
                "user": user,
                "pod_name": POD_NAME,
                "version": VERSION
            }
            
        except HTTPException:
            raise
        except psycopg2.IntegrityError as e:
            conn.rollback()
            if "email" in str(e):
                raise HTTPException(status_code=400, detail="Email already exists")
            else:
                raise HTTPException(status_code=400, detail="User update failed")
        except Exception as e:
            logger.error(f"Failed to update user {user_id}: {e}")
            raise HTTPException(status_code=500, detail="Failed to update user")

@app.delete("/users/{user_id}")
async def delete_user(user_id: int):
    """Delete user"""
    with tracer.start_as_current_span("delete_user") as span:
        span.set_attribute("user_id", user_id)
        
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))
            
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="User not found")
            
            conn.commit()
            cursor.close()
            
            return {
                "message": "User deleted successfully",
                "pod_name": POD_NAME,
                "version": VERSION
            }
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Failed to delete user {user_id}: {e}")
            raise HTTPException(status_code=500, detail="Failed to delete user")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)