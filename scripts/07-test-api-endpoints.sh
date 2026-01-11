#!/bin/bash

echo "🧪 Testing API endpoints..."

BASE_URL="http://localhost:8080"

echo "1. Testing Frontend Health..."
curl -s "$BASE_URL/health" && echo " ✅" || echo " ❌"

echo "2. Testing API Gateway Health..."
curl -s "$BASE_URL/api/health" && echo " ✅" || echo " ❌"

echo "3. Testing Order Service Health..."
curl -s "$BASE_URL/api/orders/health" && echo " ✅" || echo " ❌"

echo "4. Testing User Service Health..."
curl -s "$BASE_URL/api/users/health" && echo " ✅" || echo " ❌"

echo "5. Testing Inventory Service Health..."
curl -s "$BASE_URL/api/inventory/health" && echo " ✅" || echo " ❌"

echo ""
echo "6. Testing CRUD Operations..."

echo "📝 Creating a test order..."
ORDER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/orders" \
  -H "Content-Type: application/json" \
  -d '{"user_id": 1, "product_id": 1, "quantity": 2}')

if [ $? -eq 0 ]; then
  echo "✅ Order creation successful"
  echo "Response: $ORDER_RESPONSE"
else
  echo "❌ Order creation failed"
fi

echo ""
echo "📋 Getting orders..."
ORDERS_RESPONSE=$(curl -s "$BASE_URL/api/orders")

if [ $? -eq 0 ]; then
  echo "✅ Get orders successful"
  echo "Response: $ORDERS_RESPONSE"
else
  echo "❌ Get orders failed"
fi

echo ""
echo "👥 Getting users..."
USERS_RESPONSE=$(curl -s "$BASE_URL/api/users")

if [ $? -eq 0 ]; then
  echo "✅ Get users successful"
  echo "Response: $USERS_RESPONSE"
else
  echo "❌ Get users failed"
fi

echo ""
echo "📦 Getting inventory..."
INVENTORY_RESPONSE=$(curl -s "$BASE_URL/api/inventory")

if [ $? -eq 0 ]; then
  echo "✅ Get inventory successful"
  echo "Response: $INVENTORY_RESPONSE"
else
  echo "❌ Get inventory failed"
fi

echo ""
echo "🎉 API testing complete!"