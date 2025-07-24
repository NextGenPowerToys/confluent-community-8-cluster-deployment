# Kafka UI Access

## Overview
Kafka UI is now available as part of the Docker deployment setup. It provides a web-based interface to manage and monitor your Kafka cluster.

## Access Information
- **URL**: http://localhost:8080
- **Container**: kafka-ui
- **Network IP**: 192.168.1.20

## Features Available
- View and manage topics
- Browse messages
- Monitor brokers and cluster health
- View consumer groups
- Cluster configuration overview

## Starting Kafka UI
The Kafka UI container starts automatically when you run:
```bash
./manage-servers.sh start
```

## Connecting to Kafka Cluster
The Kafka UI is pre-configured to connect to your 3-node Kafka cluster:
- kafka-test-node1:9092
- kafka-test-node2:9092  
- kafka-test-node3:9092

## Container Management
- View status: `./manage-servers.sh status`
- View logs: `docker logs kafka-ui`
- Direct access: `docker exec -it kafka-ui /bin/bash`

## Notes
- Kafka UI does not require SSH access (web-based interface only)
- The container will show "Skipping SSH test" in the manage-servers.sh status output
- Make sure your Kafka cluster is running before accessing the UI for full functionality
