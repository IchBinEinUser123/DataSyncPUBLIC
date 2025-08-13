#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Kafka REST Proxy with API Key Authentication${NC}"

# Create nginx directory
mkdir -p nginx

# Create nginx.conf if it doesn't exist
if [ ! -f "nginx/nginx.conf" ]; then
    echo -e "${YELLOW}Creating nginx/nginx.conf...${NC}"
    cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream kafka_rest {
        server kafka-rest-proxy:8082;
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    server {
        listen 80;
        server_name _;

        auth_basic "Kafka REST API";
        auth_basic_user_file /etc/nginx/.htpasswd;

        location / {
            proxy_pass http://kafka_rest;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
            proxy_buffering off;
            proxy_request_buffering off;
        }

        location /health {
            auth_basic off;
            access_log off;
            return 200 "healthy\n";
        }
    }
}
EOF
fi

# Check if htpasswd is available
if ! command -v htpasswd &> /dev/null; then
    echo -e "${YELLOW}htpasswd not found. Trying to use Docker instead...${NC}"

    # Use Docker to generate htpasswd file
    echo -e "${GREEN}Generating API keys using Docker...${NC}"

    # Create temporary container to generate htpasswd
    docker run --rm -v $(pwd)/nginx:/nginx httpd:alpine sh -c "
        htpasswd -cb /nginx/.htpasswd admin_key admin_secret && \
        htpasswd -b /nginx/.htpasswd producer_key producer_secret && \
        htpasswd -b /nginx/.htpasswd consumer_key consumer_secret && \
        htpasswd -b /nginx/.htpasswd app1_key app1_secret && \
        htpasswd -b /nginx/.htpasswd app2_key app2_secret && \
        htpasswd -b /nginx/.htpasswd readonly_key readonly_secret
    "
else
    echo -e "${GREEN}Generating API keys...${NC}"

    # Create .htpasswd file with API keys
    htpasswd -cb nginx/.htpasswd admin_key admin_secret
    htpasswd -b nginx/.htpasswd producer_key producer_secret
    htpasswd -b nginx/.htpasswd consumer_key consumer_secret
    htpasswd -b nginx/.htpasswd app1_key app1_secret
    htpasswd -b nginx/.htpasswd app2_key app2_secret
    htpasswd -b nginx/.htpasswd readonly_key readonly_secret
fi

echo -e "${GREEN}API Keys Created:${NC}"
echo "  admin_key:admin_secret"
echo "  producer_key:producer_secret"
echo "  consumer_key:consumer_secret"
echo "  app1_key:app1_secret"
echo "  app2_key:app2_secret"
echo "  readonly_key:readonly_secret"
