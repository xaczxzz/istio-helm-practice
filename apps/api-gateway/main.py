import os
import time
import socket
import httpx
import logging
from typing import Dict, Any
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

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

# Initialize FastAPI
app = FastAPI(
    title="API Gateway",
    description="API Gateway for K8s 3-Tier Observability Lab",
    version="1.0.0"
)

# Instrument FastAPI and httpx
FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()

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
    'api_gateway_requests_total',
    'Total number of requests',
    ['method', 'endpoint', 'status_code']
)

REQUEST_DURATION = Histogram(
    'api_gateway_request_duration_seconds',
    'Request duration in seconds',
    ['method', 'endpoint']
)

# Service endpoints
SERVICES = {
    "order": os.getenv("ORDER_SERVICE_URL", "http://order-service:8080"),
    "inventory": os.getenv("INVENTORY_SERVICE_URL", "http://inventory-service:3000"),
    "user": os.getenv("USER_SERVICE_URL", "http://user-service:8000"),
}

# Get pod information
POD_NAME = os.getenv("HOSTNAME", socket.gethostname())
POD_IP = socket.gethostbyname(socket.gethostname())

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    response.headers["X-Pod-Name"] = POD_NAME
    response.headers["X-Pod-IP"] = POD_IP
    
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
    return {
        "status": "healthy",
        "service": "api-gateway",
        "version": "1.0.0",
        "pod_name": POD_NAME,
        "pod_ip": POD_IP,
        "timestamp": time.time()
    }

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "API Gateway for K8s 3-Tier Observability Lab",
        "version": "1.0.0",
        "services": list(SERVICES.keys()),
        "pod_info": {
            "name": POD_NAME,
            "ip": POD_IP
        }
    }

# Order Service routes
@app.get("/orders")
async def get_orders():
    """Get all orders"""
    with tracer.start_as_current_span("get_orders") as span:
        span.set_attribute("service", "order")
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{SERVICES['order']}/orders", timeout=10.0)
                response.raise_for_status()
                return response.json()
        except httpx.RequestError as e:
            logger.error(f"Error calling order service: {e}")
            raise HTTPException(status_code=503, detail="Order service unavailable")
        except httpx.HTTPStatusError as e:
            logger.error(f"Order service returned error: {e}")
            raise HTTPException(status_code=e.response.status_code, detail="Order service error")

@app.post("/orders")
async def create_order(order_data: Dict[str, Any]):
    """Create a new order"""
    with tracer.start_as_current_span("create_order") as span:
        span.set_attribute("service", "order")
        span.set_attribute("user_id", order_data.get("user_id"))
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{SERVICES['order']}/orders",
                    json=order_data,
                    timeout=10.0
                )
                response.raise_for_status()
                return response.json()
        except httpx.RequestError as e:
            logger.error(f"Error calling order service: {e}")
            raise HTTPException(status_code=503, detail="Order service unavailable")
        except httpx.HTTPStatusError as e:
            logger.error(f"Order service returned error: {e}")
            raise HTTPException(status_code=e.response.status_code, detail="Order service error")

@app.get("/orders/health")
async def order_service_health():
    """Check order service health"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{SERVICES['order']}/health", timeout=5.0)
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Order service health check failed: {e}")
        raise HTTPException(status_code=503, detail="Order service unhealthy")

# Inventory Service routes
@app.get("/inventory")
async def get_inventory():
    """Get inventory"""
    with tracer.start_as_current_span("get_inventory") as span:
        span.set_attribute("service", "inventory")
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{SERVICES['inventory']}/inventory", timeout=10.0)
                response.raise_for_status()
                return response.json()
        except httpx.RequestError as e:
            logger.error(f"Error calling inventory service: {e}")
            raise HTTPException(status_code=503, detail="Inventory service unavailable")
        except httpx.HTTPStatusError as e:
            logger.error(f"Inventory service returned error: {e}")
            raise HTTPException(status_code=e.response.status_code, detail="Inventory service error")

@app.get("/inventory/health")
async def inventory_service_health():
    """Check inventory service health"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{SERVICES['inventory']}/health", timeout=5.0)
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Inventory service health check failed: {e}")
        raise HTTPException(status_code=503, detail="Inventory service unhealthy")

# User Service routes
@app.get("/users")
async def get_users():
    """Get all users"""
    with tracer.start_as_current_span("get_users") as span:
        span.set_attribute("service", "user")
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{SERVICES['user']}/users", timeout=10.0)
                response.raise_for_status()
                return response.json()
        except httpx.RequestError as e:
            logger.error(f"Error calling user service: {e}")
            raise HTTPException(status_code=503, detail="User service unavailable")
        except httpx.HTTPStatusError as e:
            logger.error(f"User service returned error: {e}")
            raise HTTPException(status_code=e.response.status_code, detail="User service error")

@app.get("/users/health")
async def user_service_health():
    """Check user service health"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{SERVICES['user']}/health", timeout=5.0)
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"User service health check failed: {e}")
        raise HTTPException(status_code=503, detail="User service unhealthy")

# Monitoring Service routes with full proxy support
@app.api_route("/monitoring/prometheus/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def prometheus_proxy(request: Request, path: str = ""):
    """Proxy to Prometheus"""
    prometheus_url = os.getenv("PROMETHEUS_URL", "http://monitoring-stack-kube-prom-prometheus.monitoring:9090")
    target_url = f"{prometheus_url}/{path}"
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Forward the request
            response = await client.request(
                method=request.method,
                url=target_url,
                params=request.query_params,
                headers={k: v for k, v in request.headers.items() if k.lower() not in ['host', 'content-length']},
                content=await request.body() if request.method in ["POST", "PUT"] else None
            )
            
            return Response(
                content=response.content,
                status_code=response.status_code,
                headers=dict(response.headers)
            )
    except Exception as e:
        logger.error(f"Prometheus proxy error: {e}")
        raise HTTPException(status_code=503, detail=f"Prometheus unavailable: {str(e)}")

@app.api_route("/monitoring/grafana/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def grafana_proxy(request: Request, path: str = ""):
    """Proxy to Grafana"""
    grafana_url = os.getenv("GRAFANA_URL", "http://monitoring-stack-grafana.monitoring:80")
    target_url = f"{grafana_url}/{path}"
    
    try:
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            response = await client.request(
                method=request.method,
                url=target_url,
                params=request.query_params,
                headers={k: v for k, v in request.headers.items() if k.lower() not in ['host', 'content-length']},
                content=await request.body() if request.method in ["POST", "PUT"] else None
            )
            
            return Response(
                content=response.content,
                status_code=response.status_code,
                headers=dict(response.headers)
            )
    except Exception as e:
        logger.error(f"Grafana proxy error: {e}")
        raise HTTPException(status_code=503, detail=f"Grafana unavailable: {str(e)}")

@app.api_route("/monitoring/jaeger/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def jaeger_proxy(request: Request, path: str = ""):
    """Proxy to Jaeger"""
    jaeger_url = os.getenv("JAEGER_URL", "http://jaeger-query.istio-system:16686")
    target_url = f"{jaeger_url}/jaeger/{path}"
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.request(
                method=request.method,
                url=target_url,
                params=request.query_params,
                headers={k: v for k, v in request.headers.items() if k.lower() not in ['host', 'content-length']},
                content=await request.body() if request.method in ["POST", "PUT"] else None
            )
            
            return Response(
                content=response.content,
                status_code=response.status_code,
                headers=dict(response.headers)
            )
    except Exception as e:
        logger.error(f"Jaeger proxy error: {e}")
        raise HTTPException(status_code=503, detail=f"Jaeger unavailable: {str(e)}")

@app.api_route("/monitoring/kiali/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def kiali_proxy(request: Request, path: str = ""):
    """Proxy to Kiali"""
    kiali_url = os.getenv("KIALI_URL", "http://kiali.istio-system:20001")
    target_url = f"{kiali_url}/kiali/{path}"
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.request(
                method=request.method,
                url=target_url,
                params=request.query_params,
                headers={k: v for k, v in request.headers.items() if k.lower() not in ['host', 'content-length']},
                content=await request.body() if request.method in ["POST", "PUT"] else None
            )
            
            return Response(
                content=response.content,
                status_code=response.status_code,
                headers=dict(response.headers)
            )
    except Exception as e:
        logger.error(f"Kiali proxy error: {e}")
        raise HTTPException(status_code=503, detail=f"Kiali unavailable: {str(e)}")

@app.get("/monitoring/status")
async def monitoring_status():
    """Get monitoring services status"""
    services = {
        "prometheus": os.getenv("PROMETHEUS_URL", "http://monitoring-stack-kube-prom-prometheus.monitoring:9090"),
        "grafana": os.getenv("GRAFANA_URL", "http://monitoring-stack-grafana.monitoring:80"),
        "jaeger": os.getenv("JAEGER_URL", "http://jaeger-query.istio-system:16686"),
        "kiali": os.getenv("KIALI_URL", "http://kiali.istio-system:20001"),
    }
    
    # Check health of each service
    status = {}
    async with httpx.AsyncClient(timeout=5.0) as client:
        for name, url in services.items():
            try:
                response = await client.get(url)
                status[name] = {
                    "url": url,
                    "status": "healthy" if response.status_code < 500 else "unhealthy",
                    "status_code": response.status_code
                }
            except Exception as e:
                status[name] = {
                    "url": url,
                    "status": "unreachable",
                    "error": str(e)
                }
    
    return status

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)