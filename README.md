# Confluent Community 8.0.0 KRaft Deployment

Automated deployment system for Confluent Community Edition 8.0.0 with KRaft consensus protocol. Supports offline installation in air-gapped environments.

## 🚀 Quick Start

### 1. Download Prerequisites
```bash
./download-prerequisites.sh
```

### 2. Test with Docker
```bash
# Start test environment
docker-compose up -d
sleep 60

# Setup SSH keys
for port in 12222 12223 12224; do 
  sshpass -p 'password' ssh-copy-id -o StrictHostKeyChecking=no -o Port=$port -i ~/.ssh/kafka_test_key root@localhost
done

# Deploy Kafka cluster
cd src/deployment-scripts
./deploy-kafka-cluster.sh
# Choose: d (docker), test (environment), 3 (servers)
```

### 3. Access Kafka UI
- **Web Interface**: http://localhost:18080
- **Kafka Brokers**: `localhost:19092,localhost:19094,localhost:19096`

## 📋 Deployment Options

| Type | Command | Environment | Servers | Use Case |
|------|---------|-------------|---------|----------|
| **Docker** | `d` | `test` | `3` | Testing & Development |
| **Local** | `l` | `dev` | `1` | Local Development |
| **Remote** | `r` | `prod` | `3` | Production Deployment |

## 📚 Documentation

- **[Deployment Guide](DEPLOYMENT.md)** - Complete deployment instructions
- **[Architecture](kafka-cluster-architecture.md)** - Technical architecture and design
- **[Rules](.amazonq/rules/kafak-deployment-sh-script.md)** - Deployment script requirements

## ✨ Features

- **KRaft Mode**: No Zookeeper dependency
- **Offline Installation**: Air-gap compatible with Java 21
- **Multi-Environment**: Docker, Local, Remote deployments
- **Automated Setup**: Single script deployment
- **Kafka UI**: Web-based cluster management
- **Production Ready**: 3-node cluster with replication

## 🛠 Components

- **Confluent Community 8.0.0** (380MB)
- **Java 21 LTS** (195MB) - Offline installation
- **Kafka UI** - Web interface for cluster management
- **KRaft Consensus** - Modern Kafka without Zookeeper

## 📋 Requirements

### System Requirements
- **Docker**: For testing environment
- **RHEL 8**: For production deployment
- **macOS/Linux**: For local development
- **SSH Access**: For remote deployment

### Network Ports
- **9092**: Kafka broker (PLAINTEXT)
- **9093**: Kafka controller (KRaft)
- **8080**: Kafka UI web interface
- **22**: SSH access

### Prerequisites (Auto-Downloaded)
- `confluent-community-8.0.0.zip`
- `jdk-21_linux-aarch64_bin.tar.gz`