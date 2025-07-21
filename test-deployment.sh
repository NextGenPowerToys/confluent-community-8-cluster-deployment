#!/bin/bash

set -e

echo "=== Starting Docker Test Environment ==="

# Start containers
docker-compose up -d

echo "Waiting for containers to start and systemd to initialize..."
sleep 60

# Setup SSH keys for passwordless access
echo "=== Setting up SSH access ==="

# Generate SSH key if not exists
if [[ ! -f ~/.ssh/kafka_test_key ]]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/kafka_test_key -N ""
fi

# Copy SSH key to containers using localhost ports
for port in 12222 12223 12224; do
    echo "Setting up SSH for localhost:$port..."
    sshpass -p 'password' ssh-copy-id -o StrictHostKeyChecking=no -o Port=$port -i ~/.ssh/kafka_test_key root@localhost
done

echo "=== SSH setup complete ==="
echo "You can now run the deployment script:"
echo "cd src/deployment-scripts"
echo "./deploy-kafka-cluster.sh"
echo ""
echo "When prompted:"
echo "- Local deployment? n"
echo "- Environment name: test"
echo "- Number of servers: 3"
echo ""
echo "Access points after deployment:"
echo "- Kafka UI: http://localhost:18080"
echo "- Kafka brokers: localhost:19092,localhost:19094,localhost:19096"