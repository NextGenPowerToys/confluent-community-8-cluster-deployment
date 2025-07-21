#!/bin/bash

echo "Waiting for SSH services to be ready..."

# Wait for each container's SSH to be ready
for port in 12222 12223 12224; do
    echo "Waiting for SSH on localhost:$port..."
    while ! nc -z localhost $port 2>/dev/null; do
        sleep 2
    done
    echo "SSH ready on port $port"
done

echo "Setting up SSH keys..."
for port in 12222 12223 12224; do
    echo "Setting up SSH for localhost:$port..."
    sshpass -p 'password' ssh-copy-id -o StrictHostKeyChecking=no -o Port=$port -i ~/.ssh/kafka_test_key root@localhost
done

echo "SSH setup complete!"