# Confluent Community Cluster 8 - KRaft Deployment Architecture

## Overview

This document describes the architecture of a shell script deployment system for Confluent Community Edition 8.0.0 with KRaft (Kafka Raft) consensus protocol on 3 Red Hat Enterprise Linux 8 servers. The deployment creates a highly available, distributed Kafka cluster running natively without containers.

## Architecture Diagram

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   RHEL 8 - S1   │  │   RHEL 8 - S2   │  │   RHEL 8 - S3   │
│  (kafka-node-1) │  │  (kafka-node-2) │  │  (kafka-node-3) │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ KRaft Controller│  │ KRaft Controller│  │ KRaft Controller│
│ (Node ID: 1)    │  │ (Node ID: 2)    │  │ (Node ID: 3)    │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ Kafka Broker    │  │ Kafka Broker    │  │ Kafka Broker    │
│ (Broker ID: 1)  │  │ (Broker ID: 2)  │  │ (Broker ID: 3)  │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ Port: 9092      │  │ Port: 9092      │  │ Port: 9092      │
│ (Plaintext)     │  │ (Plaintext)     │  │ (Plaintext)     │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │   (Optional)    │
                    └─────────────────┘
```

## Cluster Configuration

### Node Distribution
- **N RHEL 8 Servers**: Each server acts as both KRaft controller and Kafka broker (minimum 1)
- **High Availability**: Quorum-based consensus for multi-node (single-node for development)
- **Native Deployment**: No containerization - direct installation on OS

### Network Configuration
- **Broker Communication**: Port 9092 (plaintext)
- **Inter-node Communication**: Port 9093 (controller listeners)

## Directory Structure

### Data Directories
```
Production Environment:
/kafka/
├── logs/                           # Kafka topic partitions and metadata
│   ├── __cluster_metadata-0/       # KRaft metadata logs
│   ├── topic1-0/                   # Topic1 partition 0
│   ├── topic1-1/                   # Topic1 partition 1
│   ├── topic2-0/                   # Topic2 partition 0
│   ├── topic2-1/                   # Topic2 partition 1
│   └── ...                         # Additional topic partitions

Local Development Environment:
/tmp/kafka/
├── logs/                           # Kafka topic partitions and metadata
│   ├── __cluster_metadata-0/       # KRaft metadata logs
│   └── ...                         # Topic partitions
```

### Installation Structure (Updated)
```
/opt/kafka/                         # Kafka installation root
├── bin/                           # Kafka executables (NO .sh extensions)
│   ├── kafka-server-start         # Server startup script
│   ├── kafka-server-stop          # Server shutdown script
│   ├── kafka-storage              # Storage management tool
│   ├── kafka-topics               # Topic management tool
│   └── kafka-broker-api-versions  # API version tool
├── etc/kafka/                     # Configuration files (NOT config/kraft/)
│   ├── server.properties          # Main Kafka configuration
│   ├── broker.properties          # Broker configuration template
│   ├── controller.properties      # Controller configuration template
│   └── log4j2.yaml               # Logging configuration
├── lib/                           # Java libraries
├── share/                         # Shared resources
└── src/                           # Source files
```

### Log Directories
```
Production Environment:
/var/log/confluent/
├── kafka/
│   ├── server.log
│   ├── state-change.log
│   ├── log-cleaner.log
│   └── controller.log

Local Development Environment:
/tmp/log/confluent/
└── kafka/
    └── kafka.log                  # Combined log output
```

### User and Group Management
```
Linux (Production):
- Created with: groupadd -r kafka && useradd -r -g kafka -s /bin/false -d /opt/kafka kafka
- Validation: getent group kafka && id kafka

macOS (Development):
- Created with: dscl commands for group and user creation
- Validation: dscl . -read /Groups/kafka && dscl . -read /Users/kafka
```

### Java Version Compatibility
```
Supported Java Versions:
- Java 8 (recommended)
- Java 11 LTS (recommended)

Known Issues:
- Java 17+: Deprecated JVM options cause startup failures
- Java 21+: PrintGCDateStamps option removed, requires JVM flag updates
```

## Component Architecture

### 1. KRaft Controllers
Each server runs a KRaft controller responsible for:
- **Cluster Metadata Management**: Topics, partitions, replicas
- **Leader Election**: Broker and partition leadership
- **Configuration Management**: Dynamic configuration changes
- **Quorum Consensus**: Distributed consensus using Raft protocol

#### Controller Configuration
```properties
# KRaft Controller Settings
process.roles=controller,broker
controller.quorum.voters=1@kafka-${ENVIRONMENT}-node-1:9093,2@kafka-${ENVIRONMENT}-node-2:9093,3@kafka-${ENVIRONMENT}-node-3:9093
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://:9092,CONTROLLER://:9093
```

### 2. Kafka Brokers
Each server runs a Kafka broker that handles:
- **Message Storage**: Topic partitions and segments
- **Client Connections**: Producer and consumer requests
- **Replication**: Inter-broker replication
- **Log Management**: Segment rotation and cleanup

#### Broker Configuration
```properties
# Broker Settings
broker.id=<dynamic-based-on-server>
log.dirs=/kafka/logs
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# Topic Management
auto.create.topics.enable=false
delete.topic.enable=true
log.segment.ms=3600000
log.retention.ms=86400000
num.partitions=24
default.replication.factor=3
min.insync.replicas=2

# Topic Directory Structure
log.dir=/kafka/logs
log.dirs=/kafka/logs
```

### 3. Default Topic Configuration
- **Partitions per Topic**: 24
- **Replication Factor**: 3
- **Retention Period**: 24 hours (86400000 ms)
- **Segment Retention**: 1 hour (3600000 ms)
- **Compression**: Producer-driven (snappy recommended)
- **Auto Topic Creation**: Disabled (requires explicit topic creation)
- **Topic Storage**: Each topic stored in separate subdirectory under `/kafka/logs/`

## SystemD Service Architecture

### Service Units
Each Kafka instance runs as a systemd service for:
- **Automatic Startup**: Boot-time initialization
- **Process Management**: Restart on failure
- **Resource Control**: Memory and CPU limits
- **Logging**: Journald integration

#### Service Configuration
```ini
[Unit]
Description=Apache Kafka Server (KRaft Mode)
Documentation=https://kafka.apache.org/documentation/
Requires=network.target
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal
RestartSec=30s

[Install]
WantedBy=multi-user.target
```

## Deployment Script Architecture

### Script Structure
```
deploy-kafka-cluster.sh
├── Environment Input
│   ├── Prompt user for environment name (dev/staging/prod/etc)
│   └── Prompt user for number of servers (minimum 1)
├── Configuration Loading
│   ├── Load cluster-config.yaml file
│   └── Parse credentials, servers, and settings with environment substitution
├── Pre-flight Checks
│   ├── OS compatibility verification
│   ├── Network connectivity tests
│   └── Permission validation
├── Software Installation
│   ├── Java 21 installation (from local archive)
│   └── Confluent Community 8.0.0 extraction (from local ZIP)
├── Cluster Configuration
│   ├── KRaft metadata generation
│   ├── Server properties creation
│   └── Log4j configuration
├── Service Setup
│   ├── SystemD unit creation
│   ├── User/group creation
│   └── Directory permissions
└── Cluster Initialization
    ├── KRaft format and start
    ├── Service enablement
    └── Health verification
```

### Configuration File (YAML)
```yaml
cluster:
  name: "confluent-community-${ENVIRONMENT}-cluster"
  version: "8.0.0"
  
servers:
  - hostname: "kafka-${ENVIRONMENT}-node-1"
    ip: "192.168.1.10"
    node_id: 1
    broker_id: 1
  - hostname: "kafka-${ENVIRONMENT}-node-2"
    ip: "192.168.1.11"
    node_id: 2
    broker_id: 2
  - hostname: "kafka-${ENVIRONMENT}-node-3"
    ip: "192.168.1.12"
    node_id: 3
    broker_id: 3

credentials:
  ssh_user: "root"
  ssh_key_path: "/path/to/private/key"
  kafka_user: "kafka"
  kafka_group: "kafka"

network:
  plaintext_port: 9092
  controller_port: 9093

storage:
  data_dir: "/kafka"
  log_dir: "/var/log/confluent"

# Local installation files (offline environment)
installation:
  local_files_path: "/opt/deployment/files"
  confluent_archive: "confluent-community-8.0.0.zip"
  java_archive: "jdk-21.0.8.jdk"

defaults:
  partitions_per_topic: 24
  retention_hours: 24
  segment_retention_hours: 1
  replication_factor: 3
  min_insync_replicas: 2
  auto_create_topics: false  # Disable automatic topic creation
  topic_separate_dirs: true  # Each topic in separate directory
```

## Security Considerations

### Network Security
- **Plaintext Communication**: Development/testing environments only
- **Firewall Rules**: Restricted port access between cluster nodes
- **SSH Access**: Key-based authentication for deployment

### File System Security
- **Dedicated User**: `kafka` user with minimal privileges
- **Directory Permissions**: 755 for binaries, 750 for data/logs
- **Log Rotation**: Automatic log rotation to prevent disk filling

## Offline Environment Architecture

### Air-Gapped Deployment
- **No Internet Connectivity**: Complete offline installation from local archives
- **Local Package Repository**: All required software packages pre-staged
- **Self-Contained Installation**: No external dependencies or downloads

### Pre-requisite Files
The following files must be available locally before deployment:

```
/opt/deployment/files/
├── confluent-community-8.0.0.zip   # Confluent Community distribution
├── jdk-21.0.8.jdk/                 # Java 21 JDK
└── deployment-scripts/
    ├── deploy-kafka-cluster.sh
    ├── cluster-config.yaml
    └── templates/
        ├── cluster-config.yaml
        ├── server.properties.template
        ├── kafka.service.template
        └── log4j.properties.template
```

### Installation Process for Offline Environment
1. **File Transfer**: Copy all installation files to deployment server
2. **SSH Distribution**: Transfer archives to all target nodes
3. **Local Extraction**: Extract and install from local archives
4. **Configuration Generation**: Create configs from templates
5. **Service Setup**: Install systemd services locally

### Topic Management in Offline Environment
- **Manual Topic Creation**: All topics must be created explicitly
- **Topic Administration**: Use local Kafka scripts for topic management
- **Separate Storage**: Each topic partition stored in dedicated directory
- **No Auto-Discovery**: Topics must be pre-planned and configured

## Monitoring and Management

### Health Checks
- **Service Status**: SystemD service monitoring
- **Port Connectivity**: Network port availability
- **Disk Usage**: Data and log directory space monitoring
- **JVM Metrics**: Heap usage and garbage collection

## High Availability Features

### Fault Tolerance
- **Quorum Resilience**: Survives single node failure
- **Data Replication**: 3-way replication for all partitions
- **Automatic Failover**: Leader election for failed brokers
- **Rolling Updates**: Graceful node maintenance

### Disaster Recovery
- **Data Persistence**: Local disk storage with replication
- **Configuration Backup**: Cluster metadata in KRaft logs
- **Service Recovery**: Automatic restart on failure

## Performance Optimization

### Hardware Recommendations
- **CPU**: 8+ cores per server
- **Memory**: 32GB+ RAM (16GB for Kafka, 16GB for OS)
- **Storage**: SSD storage for `/kafka` directory
- **Network**: 10Gbps network interfaces

### JVM Tuning
```bash
# Recommended JVM settings
export KAFKA_HEAP_OPTS="-Xmx16G -Xms16G"
export KAFKA_JVM_PERFORMANCE_OPTS="-server -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35"
```

## Deployment Workflow

### Pre-deployment
1. **Environment Preparation**: RHEL 8 servers provisioning
2. **Network Configuration**: Hostname resolution and connectivity
3. **SSH Setup**: Key-based authentication configuration
4. **YAML Configuration**: Cluster parameters definition
5. **File Staging**: Copy all installation archives to deployment location
6. **Connectivity Verification**: Ensure all nodes accessible via SSH

### Deployment Execution
1. **Environment Input**: Prompt user for environment name and validate
2. **Script Validation**: Configuration file parsing and validation with environment substitution
3. **File Distribution**: Copy installation archives to all target nodes
3. **Local Installation**: Extract and install software from local archives
4. **Cluster Configuration**: Generate server properties with auto-create disabled
5. **Topic Directory Setup**: Create separate directories for topic storage
6. **Service Creation**: Install and configure systemd services
7. **KRaft Initialization**: Format cluster metadata and start services
8. **Health Verification**: Validate cluster formation and connectivity

### Post-deployment
1. **Service Verification**: All services running and healthy
2. **Manual Topic Creation**: Create initial topics with specified configuration
3. **Topic Directory Validation**: Verify separate storage directories created
4. **Documentation**: Connection strings, topic management guides, and offline procedures

## Maintenance Operations

### Routine Maintenance
- **Log Rotation**: Daily log cleanup and archival
- **Health Monitoring**: Automated health check scripts
- **Performance Monitoring**: Metrics collection and alerting
- **Backup Procedures**: Configuration and metadata backup

### Scaling Operations
- **Horizontal Scaling**: Adding new broker nodes
- **Partition Rebalancing**: Optimal partition distribution
- **Storage Expansion**: Data directory expansion procedures

## Topic Management Commands

Since auto topic creation is disabled, all topics must be created manually using Kafka's command-line tools:

### Create Topic
```bash
# Create topic with separate directory storage
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server kafka-node-1:9092,kafka-node-2:9092,kafka-node-3:9092 \
  --topic my-topic \
  --partitions 24 \
  --replication-factor 3 \
  --config retention.ms=86400000 \
  --config segment.ms=3600000
```

### List Topics
```bash
/opt/kafka/bin/kafka-topics.sh --list \
  --bootstrap-server kafka-node-1:9092
```

### Describe Topic
```bash
/opt/kafka/bin/kafka-topics.sh --describe \
  --bootstrap-server kafka-node-1:9092 \
  --topic my-topic
```

### Delete Topic
```bash
/opt/kafka/bin/kafka-topics.sh --delete \
  --bootstrap-server kafka-node-1:9092 \
  --topic my-topic
```

### Topic Directory Structure
Each topic will automatically create separate directories:
```
/kafka/logs/
├── my-topic-0/          # Partition 0 files
├── my-topic-1/          # Partition 1 files
├── my-topic-2/          # Partition 2 files
└── ...                  # Additional partitions (up to 24)
```

This architecture provides a robust, scalable, and maintainable Kafka cluster deployment suitable for production workloads while maintaining simplicity in management and operations.
