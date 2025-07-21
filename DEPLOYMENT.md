# Confluent Community 8.0.0 Deployment Instructions

## Quick Start

### 1. Download Prerequisites
```bash
# Download all required files for offline deployment
./download-prerequisites.sh
```

### 2. Test with Docker
```bash
# Start test environment
docker-compose up -d

# Wait for containers to initialize
sleep 60

# Setup SSH access
for port in 12222 12223 12224; do 
  sshpass -p 'password' ssh-copy-id -o StrictHostKeyChecking=no -o Port=$port -i ~/.ssh/kafka_test_key root@localhost
done

# Deploy to Docker test environment
cd src/deployment-scripts
./deploy-kafka-cluster.sh
# Choose: d (docker), test (environment), 3 (servers)
```

### 3. Access Kafka UI
- **Kafka UI**: `http://localhost:18080`
- **Kafka Brokers**: `localhost:19092,localhost:19094,localhost:19096`

## Prerequisites

### Required Files (Auto-Downloaded)
The `download-prerequisites.sh` script downloads:
- `confluent-community-8.0.0.zip` (380MB)
- `jdk-21_linux-aarch64_bin.tar.gz` (195MB)

### System Requirements
- **Remote**: RHEL 8 servers with SSH access
- **Local**: macOS/Linux with sudo access  
- **Docker**: For testing environment
- **Java**: Installed automatically (offline)
- **Network**: Ports 9092, 9093, 8080 available

## Deployment Options

### 1. Docker Test Environment

```bash
# Start containers
docker-compose up -d

# Deploy Kafka
cd src/deployment-scripts
./deploy-kafka-cluster.sh
```

**Prompts:**
- Deployment type: `d` (docker)
- Environment name: `test`
- Number of servers: `3`

**Result:** 3-node KRaft cluster + Kafka UI

### 2. Local Development Deployment

```bash
cd src/deployment-scripts
./deploy-kafka-cluster.sh
```

**Prompts:**
- Deployment type: `l` (local)
- Environment name: `dev`
- Number of servers: `1`

**Result:** Single-node Kafka cluster on localhost

### 3. Remote Production Deployment

#### Step 1: Configure SSH Access
```bash
# Ensure SSH key access to all target servers
ssh-copy-id root@192.168.1.10
ssh-copy-id root@192.168.1.11
ssh-copy-id root@192.168.1.12
```

#### Step 2: Update Configuration
Edit `cluster-config.yaml` with your server details:
```yaml
servers:
  - hostname: "kafka-${ENVIRONMENT}-node-1"
    ip: "YOUR_SERVER_1_IP"
  - hostname: "kafka-${ENVIRONMENT}-node-2"
    ip: "YOUR_SERVER_2_IP"
  - hostname: "kafka-${ENVIRONMENT}-node-3"
    ip: "YOUR_SERVER_3_IP"

credentials:
  ssh_user: "root"
```

#### Step 3: Run Deployment
```bash
cd src/deployment-scripts
./deploy-kafka-cluster.sh
```

**Prompts:**
- Deployment type: `r` (remote)
- Environment name: `prod`
- Number of servers: `3`

## Post-Deployment

### Access Points

#### Docker Environment
- **Kafka UI**: `http://localhost:18080`
- **Bootstrap Servers**: `localhost:19092,localhost:19094,localhost:19096`

#### Production Environment
- **Kafka UI**: `http://kafka-{environment}-node-1:8080`
- **Bootstrap Servers**: `kafka-{environment}-node-1:9092,kafka-{environment}-node-2:9092,kafka-{environment}-node-3:9092`

### Verify Installation

#### Docker Environment
```bash
# Check if Kafka is responding
echo "test" | nc localhost 19092 && echo "✅ Kafka responding"

# Access Kafka UI
open http://localhost:18080
```

#### Production Environment
```bash
# Check services
systemctl status kafka

# Test cluster
JAVA_HOME=/opt/jdk-21.0.8 /opt/kafka/bin/kafka-topics --bootstrap-server localhost:9092 --list
```

### Create Topics

#### Docker Environment
```bash
# Connect to container and create topic
docker exec kafka-node-1 /opt/kafka/bin/kafka-topics --create \
  --bootstrap-server kafka-test-node-1:9092 \
  --topic test-topic \
  --partitions 24 \
  --replication-factor 3
```

#### Production Environment
```bash
JAVA_HOME=/opt/jdk-21.0.8 /opt/kafka/bin/kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic test-topic \
  --partitions 24 \
  --replication-factor 3
```

## Configuration Details

### Default Settings
- **Mode**: KRaft (no Zookeeper)
- **Java Version**: 21 (offline installation)
- **Partitions**: 24 per topic
- **Replication Factor**: 3 (or server count if < 3)
- **Retention**: 24 hours
- **Auto Topic Creation**: Disabled
- **Min In-Sync Replicas**: 2 (or 1 for single node)

### Directory Structure
- **Data**: `/kafka/logs` (remote) or `/tmp/kafka` (local)
- **Logs**: `/var/log/confluent` (remote) or `/tmp/log/confluent` (local)
- **Installation**: `/opt/kafka`

## Troubleshooting

### Common Issues
1. **SSH Connection Failed**: Verify SSH keys and network connectivity
2. **Permission Denied**: Ensure sudo access on target servers
3. **Port Already in Use**: Check if ports 9092, 9093, 8080 are available
4. **Java Not Found**: Script installs Java automatically

### Log Locations

#### Docker Environment
```bash
# View Kafka logs
docker exec kafka-node-1 tail -f /var/log/confluent/kafka/kafka.log

# View Kafka UI logs
docker logs kafka-ui -f
```

#### Production Environment
- **Kafka Logs**: `/var/log/confluent/kafka/kafka.log`
- **System Logs**: `journalctl -u kafka -f`

### Service Management

#### Docker Environment
```bash
# Restart containers
docker-compose restart

# Stop environment
docker-compose down

# View container status
docker-compose ps
```

#### Production Environment
```bash
# Start/Stop/Restart Kafka
systemctl start kafka
systemctl stop kafka
systemctl restart kafka

# Check status
systemctl status kafka
```

## Architecture

### Components
- **Confluent Community 8.0.0**: Apache Kafka distribution
- **KRaft Mode**: No Zookeeper dependency
- **Java 21**: Latest LTS version
- **Kafka UI**: Web-based cluster management
- **Offline Installation**: Air-gap compatible

### Network Ports
- **9092**: Kafka broker (PLAINTEXT)
- **9093**: Kafka controller (KRaft)
- **8080**: Kafka UI web interface
- **22**: SSH access (Docker: 12222-12224)

### File Structure
```
kafka-community-8/
├── deployment-files/          # Downloaded prerequisites
├── src/deployment-scripts/    # Deployment automation
├── docker-compose.yml         # Test environment
├── download-prerequisites.sh  # Download script
└── DEPLOYMENT.md             # This file
```