#!/bin/bash

# This script helps you add custom API keys

if [ $# -ne 2 ]; then
    echo "Usage: $0 <api_key> <api_secret>"
    echo "Example: $0 my_custom_key my_custom_secret"
    exit 1
fi

API_KEY=$1
API_SECRET=$2

# Check if htpasswd is available
if ! command -v htpasswd &> /dev/null; then
    # Use Docker to add the key
    docker run --rm -v $(pwd)/nginx:/nginx httpd:alpine \
        htpasswd -b /nginx/.htpasswd "$API_KEY" "$API_SECRET"
else
    htpasswd -b nginx/.htpasswd "$API_KEY" "$API_SECRET"
fi

echo "Added API key: $API_KEY"
echo "Test with: curl -u $API_KEY:$API_SECRET http://localhost:9093/topics"