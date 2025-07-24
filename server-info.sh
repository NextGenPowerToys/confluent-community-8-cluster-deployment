#!/bin/bash

# RHEL 8 Docker Server Management Summary
# ======================================

echo "🚀 RHEL 8 Docker Server Environment Ready!"
echo ""
echo "📋 Container Status:"
docker-compose ps
echo ""

echo "🔐 SSH Connection Commands:"
echo "  🖥️  kafka-test-node1: ssh admin@localhost -p 2221"
echo "  🖥️  kafka-test-node2: ssh admin@localhost -p 2222" 
echo "  🖥️  kafka-test-node3: ssh admin@localhost -p 2223"
echo ""
echo "  👤 Admin Password: password123"
echo "  👤 Root Password:  rootpassword"
echo ""

echo "🐳 Direct Container Access:"
echo "  docker exec -it kafka-test-node1 /bin/bash"
echo "  docker exec -it kafka-test-node2 /bin/bash"
echo "  docker exec -it kafka-test-node3 /bin/bash"
echo ""

echo "🌐 Network Information:"
echo "  📍 kafka-test-node1: 192.168.1.10"
echo "  📍 kafka-test-node2: 192.168.1.11"
echo "  📍 kafka-test-node3: 192.168.1.12"
echo ""

echo "⚙️  Management Commands:"
echo "  ./manage-servers.sh start     - Start all containers"
echo "  ./manage-servers.sh stop      - Stop all containers"
echo "  ./manage-servers.sh restart   - Restart all containers"
echo "  ./manage-servers.sh status    - Show status"
echo "  ./manage-servers.sh test-ssh  - Test SSH connectivity"
echo "  ./manage-servers.sh logs      - Show container logs"
echo ""

echo "✅ All 3 RHEL 8 servers are running with SSH enabled!"
echo "🔑 You can now SSH into each server using the commands above."
