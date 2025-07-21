# Confluent Community 8.0.0 Deployment Instructions

## Prerequisites

### Required Files
Place these files in `/Users/alexk/pipelines/kafka-community-8/deployment-files/`:
- `confluent-community-8.0.0.zip`
- `provectus-kafka-ui.jar`

### System Requirements
- **Remote**: RHEL 8 servers with SSH access
- **Local**: macOS/Linux with sudo access
- **Java**: Will be installed automatically
- **Network**: Ports 9092, 9093, 8080 available

## Deployment Options

### 1. Local Development Deployment

```bash
cd /Users/alexk/pipelines/kafka-community-8/src/deployment-scripts
./deploy-kafka-cluster.sh
```

**Prompts:**
- Local deployment? `y`
- Environment name: `dev`
- Number of servers: `1`

**Result:** Single-node Kafka cluster on localhost

### 2. Remote Production Deployment

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
cd /Users/alexk/pipelines/kafka-community-8/src/deployment-scripts
./deploy-kafka-cluster.sh
```

**Prompts:**
- Local deployment? `n`
- Environment name: `prod`
- Number of servers: `3`

## Post-Deployment

### Access Points
- **Kafka UI**: `http://kafka-{environment}-node-1:8080`
- **Bootstrap Servers**: `kafka-{environment}-node-1:9092,kafka-{environment}-node-2:9092,kafka-{environment}-node-3:9092`

### Verify Installation
```bash
# Check services
systemctl status kafka
systemctl status kafka-ui

# Test cluster
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Create Topics
```bash
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic test-topic \
  --partitions 24 \
  --replication-factor 3
```

## Configuration Details

### Default Settings
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
- **Kafka Logs**: `/var/log/confluent/kafka/server.log`
- **Kafka UI Logs**: `/var/log/confluent/provectus-kafka-ui/application.log`
- **System Logs**: `journalctl -u kafka -f`

### Service Management
```bash
# Start/Stop/Restart services
systemctl start kafka
systemctl stop kafka
systemctl restart kafka

systemctl start kafka-ui
systemctl stop kafka-ui
systemctl restart kafka-ui
```