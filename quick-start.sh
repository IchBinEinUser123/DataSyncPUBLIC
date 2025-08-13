#!/bin/bash
# quick-start.sh - One-command setup for Kafka REST Proxy with API Authentication

set -e

echo "======================================"
echo "Kafka REST Proxy with API Auth Setup"
echo "======================================"

# Create nginx directory
echo "Creating nginx directory..."
mkdir -p nginx

# Create nginx.conf
echo "Creating nginx configuration..."
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream kafka_rest {
        server kafka-rest-proxy:8082;
    }

    server {
        listen 80;

        auth_basic "Kafka REST API";
        auth_basic_user_file /etc/nginx/.htpasswd;

        location / {
            proxy_pass http://kafka_rest;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 300s;
            proxy_buffering off;
        }

        location /health {
            auth_basic off;
            return 200 "healthy\n";
        }
    }
}
EOF

# Generate .htpasswd using Docker
echo "Generating API keys..."
docker run --rm -v $(pwd)/nginx:/nginx httpd:alpine sh -c "
    htpasswd -cb /nginx/.htpasswd admin_key admin_secret && \
    htpasswd -b /nginx/.htpasswd producer_key producer_secret && \
    htpasswd -b /nginx/.htpasswd consumer_key consumer_secret
"

# Start services
echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Test the setup
echo ""
echo "Testing the setup..."
if curl -s -u admin_key:admin_secret http://localhost:9093/topics > /dev/null 2>&1; then
    echo "✅ Success! REST API is working with authentication"
    echo ""
    echo "API Keys created:"
    echo "  - admin_key:admin_secret"
    echo "  - producer_key:producer_secret"
    echo "  - consumer_key:consumer_secret"
    echo ""
    echo "Test commands:"
    echo "  curl -u admin_key:admin_secret http://localhost:9093/topics"
    echo "  curl -u producer_key:producer_secret -X POST -H 'Content-Type: application/vnd.kafka.json.v2+json' --data '{\"records\":[{\"value\":{\"test\":\"message\"}}]}' http://localhost:9093/topics/test-topic"
else
    echo "❌ Error: Could not connect to REST API. Check logs with:"
    echo "  docker-compose logs nginx-auth"
    echo "  docker-compose logs kafka-rest-proxy"
fi