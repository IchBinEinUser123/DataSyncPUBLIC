# Kafka REST Proxy with API Key Authentication

## Architecture
```
Client → Nginx (9093, API Auth) → REST Proxy (8082) → Kafka (19092)
```

## Quick Setup

1. **Run the setup script**:
```bash
chmod +x setup-auth.sh
./setup-auth.sh
```

This will:
- Create nginx configuration
- Generate API keys (.htpasswd file)
- Create necessary directories

2. **Start all services**:
```bash
docker-compose up -d
```

3. **Test the connection**:
```bash
# Test with API key authentication
curl -u admin_key:admin_secret http://localhost:9093/topics

# Should return a list of topics
```

## Default API Keys

The setup creates these API keys:
- `admin_key:admin_secret` - Full admin access
- `producer_key:producer_secret` - For producing messages
- `consumer_key:consumer_secret` - For consuming messages
- `app1_key:app1_secret` - Application 1
- `app2_key:app2_secret` - Application 2
- `readonly_key:readonly_secret` - Read-only access

## Managing API Keys

### Add a new API key:
```bash
# Using the helper script
chmod +x custom-api-keys.sh
./custom-api-keys.sh my_new_key my_new_secret

# Or manually with htpasswd
htpasswd -b nginx/.htpasswd new_api_key new_secret

# Or using Docker if htpasswd not installed
docker run --rm -v $(pwd)/nginx:/nginx httpd:alpine \
  htpasswd -b /nginx/.htpasswd new_api_key new_secret
```

### Remove an API key:
```bash
htpasswd -D nginx/.htpasswd old_api_key
```

### Change a password:
```bash
htpasswd -b nginx/.htpasswd existing_key new_secret
```

## REST API Examples

### Basic Operations

```bash
# List all topics
curl -u admin_key:admin_secret http://localhost:9093/topics

# Get broker info
curl -u admin_key:admin_secret http://localhost:9093/brokers

# Get topic configuration
curl -u admin_key:admin_secret http://localhost:9093/topics/test-topic/configs
```

### Producing Messages

```bash
# Produce a simple message
curl -X POST \
  -u producer_key:producer_secret \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -H "Accept: application/vnd.kafka.v2+json" \
  --data '{"records":[{"value":{"message":"Hello Kafka"}}]}' \
  http://localhost:9093/topics/test-topic

# Produce with key
curl -X POST \
  -u producer_key:producer_secret \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  --data '{
    "records": [
      {"key": "user1", "value": {"event": "login", "timestamp": "2024-01-01T12:00:00Z"}},
      {"key": "user2", "value": {"event": "logout", "timestamp": "2024-01-01T12:05:00Z"}}
    ]
  }' \
  http://localhost:9093/topics/test-topic
```

### Consuming Messages

```bash
# 1. Create consumer instance
CONSUMER_RESPONSE=$(curl -s -X POST \
  -u consumer_key:consumer_secret \
  -H "Content-Type: application/vnd.kafka.v2+json" \
  --data '{
    "name": "my-consumer",
    "format": "json",
    "auto.offset.reset": "earliest"
  }' \
  http://localhost:9093/consumers/my-group)

CONSUMER_URL=$(echo $CONSUMER_RESPONSE | jq -r '.base_uri')
echo "Consumer URL: $CONSUMER_URL"

# 2. Subscribe to topics
curl -X POST \
  -u consumer_key:consumer_secret \
  -H "Content-Type: application/vnd.kafka.v2+json" \
  --data '{"topics":["test-topic"]}' \
  $CONSUMER_URL/subscription

# 3. Fetch messages
curl -X GET \
  -u consumer_key:consumer_secret \
  -H "Accept: application/vnd.kafka.json.v2+json" \
  $CONSUMER_URL/records

# 4. Delete consumer when done
curl -X DELETE -u consumer_key:consumer_secret $CONSUMER_URL
```

## Python Client with Authentication

```python
import requests
import json
from requests.auth import HTTPBasicAuth

class KafkaRestClient:
    def __init__(self, base_url='http://localhost:9093', api_key='admin_key', api_secret='admin_secret'):
        self.base_url = base_url
        self.auth = HTTPBasicAuth(api_key, api_secret)
        self.consumer_url = None
    
    def list_topics(self):
        """List all Kafka topics"""
        response = requests.get(
            f"{self.base_url}/topics",
            auth=self.auth
        )
        response.raise_for_status()
        return response.json()
    
    def produce_messages(self, topic, messages):
        """Produce messages to a topic"""
        headers = {
            'Content-Type': 'application/vnd.kafka.json.v2+json',
            'Accept': 'application/vnd.kafka.v2+json'
        }
        data = {"records": [{"value": msg} for msg in messages]}
        
        response = requests.post(
            f"{self.base_url}/topics/{topic}",
            auth=self.auth,
            headers=headers,
            data=json.dumps(data)
        )
        response.raise_for_status()
        return response.json()
    
    def create_consumer(self, group_id, consumer_name=None):
        """Create a consumer instance"""
        headers = {'Content-Type': 'application/vnd.kafka.v2+json'}
        data = {
            "format": "json",
            "auto.offset.reset": "earliest"
        }
        if consumer_name:
            data["name"] = consumer_name
        
        response = requests.post(
            f"{self.base_url}/consumers/{group_id}",
            auth=self.auth,
            headers=headers,
            data=json.dumps(data)
        )
        response.raise_for_status()
        result = response.json()
        self.consumer_url = result['base_uri']
        return result
    
    def subscribe(self, topics):
        """Subscribe to topics"""
        if not self.consumer_url:
            raise Exception("No consumer created. Call create_consumer first.")
        
        headers = {'Content-Type': 'application/vnd.kafka.v2+json'}
        data = {"topics": topics}
        
        response = requests.post(
            f"{self.consumer_url}/subscription",
            auth=self.auth,
            headers=headers,
            data=json.dumps(data)
        )
        response.raise_for_status()
    
    def fetch_messages(self, max_bytes=100000):
        """Fetch messages"""
        if not self.consumer_url:
            raise Exception("No consumer created. Call create_consumer first.")
        
        headers = {'Accept': 'application/vnd.kafka.json.v2+json'}
        
        response = requests.get(
            f"{self.consumer_url}/records",
            auth=self.auth,
            headers=headers,
            params={'max_bytes': max_bytes}
        )
        response.raise_for_status()
        return response.json()
    
    def delete_consumer(self):
        """Delete consumer instance"""
        if self.consumer_url:
            response = requests.delete(self.consumer_url, auth=self.auth)
            response.raise_for_status()
            self.consumer_url = None

# Example usage
if __name__ == "__main__":
    # Producer client
    producer = KafkaRestClient(api_key='producer_key', api_secret='producer_secret')
    
    # List topics
    print("Topics:", producer.list_topics())
    
    # Produce messages
    messages = [
        {"event": "user_signup", "user_id": 123, "timestamp": "2024-01-01T10:00:00Z"},
        {"event": "purchase", "user_id": 123, "amount": 99.99}
    ]
    result = producer.produce_messages('test-topic', messages)
    print("Produced:", result)
    
    # Consumer client
    consumer = KafkaRestClient(api_key='consumer_key', api_secret='consumer_secret')
    
    # Create consumer and subscribe
    consumer.create_consumer('python-group', 'python-consumer-1')
    consumer.subscribe(['test-topic'])
    
    # Fetch messages
    messages = consumer.fetch_messages()
    print(f"Consumed {len(messages)} messages")
    for msg in messages:
        print(f"  - {msg}")
    
    # Clean up
    consumer.delete_consumer()
```

## Java Client Example

```java
import java.net.http.*;
import java.net.URI;
import java.util.Base64;

public class KafkaRestClient {
    private final String baseUrl;
    private final String authHeader;
    private final HttpClient httpClient;
    
    public KafkaRestClient(String baseUrl, String apiKey, String apiSecret) {
        this.baseUrl = baseUrl;
        String auth = apiKey + ":" + apiSecret;
        this.authHeader = "Basic " + Base64.getEncoder().encodeToString(auth.getBytes());
        this.httpClient = HttpClient.newHttpClient();
    }
    
    public String listTopics() throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + "/topics"))
            .header("Authorization", authHeader)
            .GET()
            .build();
        
        HttpResponse<String> response = httpClient.send(request, 
            HttpResponse.BodyHandlers.ofString());
        
        return response.body();
    }
    
    public String produceMessage(String topic, String message) throws Exception {
        String json = String.format(
            "{\"records\":[{\"value\":%s}]}", 
            message
        );
        
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + "/topics/" + topic))
            .header("Authorization", authHeader)
            .header("Content-Type", "application/vnd.kafka.json.v2+json")
            .header("Accept", "application/vnd.kafka.v2+json")
            .POST(HttpRequest.BodyPublishers.ofString(json))
            .build();
        
        HttpResponse<String> response = httpClient.send(request, 
            HttpResponse.BodyHandlers.ofString());
        
        return response.body();
    }
    
    public static void main(String[] args) throws Exception {
        KafkaRestClient client = new KafkaRestClient(
            "http://localhost:9093",
            "producer_key",
            "producer_secret"
        );
        
        System.out.println("Topics: " + client.listTopics());
        
        String result = client.produceMessage("test-topic", 
            "{\"message\":\"Hello from Java\"}");
        System.out.println("Produced: " + result);
    }
}
```

## Node.js Client Example

```javascript
const axios = require('axios');

class KafkaRestClient {
    constructor(baseUrl = 'http://localhost:9093', apiKey = 'admin_key', apiSecret = 'admin_secret') {
        this.baseUrl = baseUrl;
        this.auth = {
            username: apiKey,
            password: apiSecret
        };
    }
    
    async listTopics() {
        const response = await axios.get(
            `${this.baseUrl}/topics`,
            { auth: this.auth }
        );
        return response.data;
    }
    
    async produceMessages(topic, messages) {
        const data = {
            records: messages.map(msg => ({ value: msg }))
        };
        
        const response = await axios.post(
            `${this.baseUrl}/topics/${topic}`,
            data,
            {
                auth: this.auth,
                headers: {
                    'Content-Type': 'application/vnd.kafka.json.v2+json',
                    'Accept': 'application/vnd.kafka.v2+json'
                }
            }
        );
        
        return response.data;
    }
}

// Usage
const client = new KafkaRestClient(
    'http://localhost:9093',
    'producer_key',
    'producer_secret'
);

client.listTopics().then(console.log);

client.produceMessages('test-topic', [
    { message: 'Hello from Node.js' }
]).then(console.log);
```

## Monitoring & Health Check

```bash
# Check nginx health (no auth required)
curl http://localhost:9093/health

# Check if REST proxy is accessible through nginx
curl -u admin_key:admin_secret http://localhost:9093/

# View nginx logs
docker-compose logs nginx-auth

# View REST proxy logs
docker-compose logs kafka-rest-proxy
```

## Security Best Practices

1. **Change Default Passwords**: Modify the API secrets in `setup-auth.sh`
2. **Use Strong Passwords**: Generate random, complex passwords for production
3. **Rotate Keys Regularly**: Update API keys periodically
4. **Monitor Access**: Check nginx logs for unauthorized attempts
5. **Network Security**: Ensure port 9093 is only accessible as needed
6. **HTTPS in Production**: Add SSL/TLS certificates to nginx for production use

## Troubleshooting

### 401 Unauthorized
- Check API key and secret are correct
- Verify .htpasswd file exists: `ls -la nginx/.htpasswd`
- Test with curl: `curl -u admin_key:admin_secret http://localhost:9093/topics`

### 502 Bad Gateway
- Check REST proxy is running: `docker-compose ps kafka-rest-proxy`
- Check logs: `docker-compose logs kafka-rest-proxy`

### Connection Refused
- Ensure nginx is running: `docker-compose ps nginx-auth`
- Check port 9093 is not in use: `netstat -an | grep 9093`

### Cannot Connect to Kafka
- Verify Kafka is running: `docker-compose ps kafka`
- Check Kafka logs: `docker-compose logs kafka`