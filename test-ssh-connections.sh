#!/bin/bash

echo "Testing SSH connections to all containers..."
echo "Password for admin user: password123"
echo "Password for root user: rootpassword"
echo ""

echo "=== Testing kafka-test-node1 (port 2221) ==="
echo "To connect: ssh admin@localhost -p 2221"
echo "Or as root: ssh root@localhost -p 2221"
echo ""

echo "=== Testing kafka-test-node2 (port 2222) ==="
echo "To connect: ssh admin@localhost -p 2222"
echo "Or as root: ssh root@localhost -p 2222"
echo ""

echo "=== Testing kafka-test-node3 (port 2223) ==="
echo "To connect: ssh admin@localhost -p 2223"
echo "Or as root: ssh root@localhost -p 2223"
echo ""

echo "=== Container Status ==="
docker-compose ps

echo ""
echo "=== Network Information ==="
docker network inspect kafka-community-8_servers-net | grep -A 10 -B 2 "IPv4Address"
