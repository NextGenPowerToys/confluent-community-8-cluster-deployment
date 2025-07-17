# Kafka Community 8.0.0 Deployment Guide

A comprehensive guide for deploying Confluent Community Kafka 8.0.0 with Java 21 LTS in both development and production environments using KRaft mode (without Zookeeper).

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Deployment Scripts](#deployment-scripts)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Best Practices](#best-practices)

## Overview

This project provides automated deployment scripts for Confluent Community Kafka 8.0.0 with the following features:

- **KRaft Mode**: Kafka without Zookeeper for simplified architecture
- **Java 21 LTS**: Latest long-term support Java version with optimized performance
- **Dual Deployment**: Support for both local development and production environments
- **Cross-Platform**: macOS and Linux compatibility
- **Automated Setup**: Complete automation from download to running cluster

### Key Components

- Confluent Community Kafka 8.0.0
- Oracle JDK 21.0.8 LTS
- KRaft controller configuration
- Embedded shell-based configuration (no YAML dependencies)

## Prerequisites

### System Requirements

**Development (macOS):**
- macOS 10.14 or later
- 8GB RAM minimum, 16GB recommended
- 10GB free disk space
- Admin privileges (sudo access)

**Production (Linux):**
- Red Hat Enterprise Linux 8
- 16GB RAM minimum, 32GB recommended per node
- 100GB free disk space per node
- SSH access with key-based authentication

### Network Requirements

**Ports:**
- `9092`: Kafka broker (plaintext)
- `9093`: KRaft controller
- SSH access (port 22) for production deployment

**Connectivity:**
- Inter-node communication for multi-node clusters
- Client access to port 9092

## Project Structure

```
kafka-community-8/
├── deployment-files/                    # Installation binaries
│   ├── confluent-community-8.0.0.zip   # Kafka distribution
│   └── jdk-21.0.8.jdk/                 # Java 21 LTS
├── src/deployment-scripts/              # Deployment automation
│   ├── deploy-kafka-cluster-local.sh   # Local development deployment
│   ├── deploy-kafka-cluster.sh         # Production deployment
│   ├── test-kafka-simple.sh           # Testing script
│   └── *.yaml.reference               # Legacy configuration examples
├── build-kafka-ui.sh                  # Legacy UI build script
├── download-kafka-ui.sh               # Legacy UI download script
└── KAFKA_DEPLOYMENT_GUIDE.md          # This documentation
```

## Installation

### Step 1: Download Required Files

The deployment scripts require two main components:

1. **Confluent Community Kafka 8.0.0**
   ```bash
   # Download manually from:
   # https://packages.confluent.io/archive/8.0/confluent-community-8.0.0.zip
   # Place in: deployment-files/confluent-community-8.0.0.zip
   ```

2. **Oracle JDK 21.0.8**
   ```bash
   # Download manually from:
   # https://download.oracle.com/java/21/latest/jdk-21_macos-x64_bin.dmg (macOS)
   # https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz (Linux)
   # Archive as: deployment-files/jdk-21.0.8-macos-x64.tar.gz
   ```

### Step 2: Verify File Structure

Ensure your `deployment-files/` directory contains:
```
deployment-files/
├── confluent-community-8.0.0.zip
└── jdk-21.0.8-macos-x64.tar.gz    # JDK archive (auto-extracted during deployment)
```

## Deployment Scripts

### Local Development Deployment

**Script**: `deploy-kafka-cluster-local.sh`

**Features:**
- Single-node Kafka cluster
- Localhost-only configuration
- Development-friendly paths (`/tmp/kafka`)
- Interactive startup with detailed logging

**Usage:**
```bash
cd src/deployment-scripts/
sudo ./deploy-kafka-cluster-local.sh
```

**Configuration:**
```bash
SERVER_COUNT=1
LOCAL_DEPLOYMENT=true
HOSTNAMES=("localhost")
DATA_DIR="/tmp/kafka"
LOG_DIR="/tmp/log/confluent"
REPLICATION_FACTOR=1
```

### Production Deployment

**Script**: `deploy-kafka-cluster.sh`

**Features:**
- Multi-node Kafka cluster (3 nodes default)
- SSH-based remote deployment
- Production paths (`/kafka`, `/var/log/confluent`)
- Systemd service integration
- High availability configuration

**Usage:**
```bash
cd src/deployment-scripts/
./deploy-kafka-cluster.sh
```

**Configuration:**
```bash
SERVER_COUNT=3
LOCAL_DEPLOYMENT=false
HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")
DATA_DIR="/kafka"
LOG_DIR="/var/log/confluent"
REPLICATION_FACTOR=3
```

### Testing Script

**Script**: `test-kafka-simple.sh`

**Features:**
- Connectivity verification
- Topic creation and listing
- Producer/consumer testing
- Health check validation

**Usage:**
```bash
./test-kafka-simple.sh
```

## Configuration

### Embedded Shell Configuration

The deployment scripts use embedded configuration variables instead of external YAML files for improved reliability:

```bash
# Network configuration
PLAINTEXT_PORT=9092
CONTROLLER_PORT=9093

# Storage configuration
DATA_DIR="/kafka"                    # Production
DATA_DIR="/tmp/kafka"               # Development

# Kafka configuration
PARTITIONS_PER_TOPIC=24
RETENTION_HOURS=24
SEGMENT_RETENTION_HOURS=1
REPLICATION_FACTOR=3                # Production
REPLICATION_FACTOR=1                # Development
MIN_INSYNC_REPLICAS=2               # Production
MIN_INSYNC_REPLICAS=1               # Development
AUTO_CREATE_TOPICS=false
```

### KRaft Configuration

The scripts automatically generate KRaft-specific configuration:

```properties
process.roles=controller,broker
node.id=1
controller.quorum.voters=1@kafka-env-node-1:9093,2@kafka-env-node-2:9093,3@kafka-env-node-3:9093
listeners=PLAINTEXT://:9092,CONTROLLER://:9093
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
```

### Java 21 Optimization

The deployment includes Java 21-specific optimizations:

```bash
-Xmx1G -Xms1G
-server
-XX:+UseG1GC
-XX:MaxGCPauseMillis=20
-XX:InitiatingHeapOccupancyPercent=35
-XX:+ExplicitGCInvokesConcurrent
-Xlog:gc*:logs/kafkaServer-gc.log:time,tags
```

## Usage Examples

### Basic Operations

**Start Kafka (Development):**
```bash
sudo ./deploy-kafka-cluster-local.sh
```

**Create a Topic:**
```bash
JAVA_HOME=/opt/jdk-21.0.8.jdk/Contents/Home /opt/kafka/bin/kafka-topics \
  --create --topic my-topic \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1
```

**List Topics:**
```bash
JAVA_HOME=/opt/jdk-21.0.8.jdk/Contents/Home /opt/kafka/bin/kafka-topics \
  --list --bootstrap-server localhost:9092
```

**Produce Messages:**
```bash
echo "Hello Kafka!" | JAVA_HOME=/opt/jdk-21.0.8.jdk/Contents/Home /opt/kafka/bin/kafka-console-producer \
  --topic my-topic --bootstrap-server localhost:9092
```

**Consume Messages:**
```bash
JAVA_HOME=/opt/jdk-21.0.8.jdk/Contents/Home /opt/kafka/bin/kafka-console-consumer \
  --topic my-topic --bootstrap-server localhost:9092 --from-beginning
```

### Production Operations

**Deploy Production Cluster:**
```bash
./deploy-kafka-cluster.sh
# Enter environment name when prompted (e.g., "production")
```

**Check Service Status:**
```bash
# On each node:
sudo systemctl status kafka
sudo journalctl -u kafka -f
```

**Stop Services:**
```bash
# Development:
sudo pkill -f kafka-server-start

# Production (on each node):
sudo systemctl stop kafka
```

## Troubleshooting

### Common Issues

**1. Java Not Found**
```bash
ERROR: Java not found at /path/to/jdk-21
```
**Solution**: Verify Java installation path and ensure `jdk-21.0.8.jdk` is properly extracted.

**2. Permission Denied**
```bash
ERROR: Cannot create directory /opt/kafka
```
**Solution**: Run deployment script with `sudo` privileges.

**3. Port Already in Use**
```bash
ERROR: Address already in use (port 9092)
```
**Solution**: Stop existing Kafka processes or change port configuration.

**4. SSH Connection Failed**
```bash
ERROR: Cannot SSH to kafka-node-1 (192.168.1.10)
```
**Solution**: Verify SSH keys, network connectivity, and target host accessibility.

### Diagnostic Commands

**Check Kafka Process:**
```bash
ps aux | grep kafka
```

**Check Port Usage:**
```bash
netstat -ln | grep 9092
lsof -i :9092
```

**View Logs:**
```bash
# Development:
tail -f /tmp/log/confluent/kafka/kafka.log

# Production:
tail -f /var/log/confluent/kafka/kafka.log
sudo journalctl -u kafka -f
```

**Test Connectivity:**
```bash
telnet localhost 9092
JAVA_HOME=/opt/jdk-21.0.8.jdk/Contents/Home /opt/kafka/bin/kafka-broker-api-versions \
  --bootstrap-server localhost:9092
```

## Architecture

### KRaft Mode Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kafka Cluster (KRaft Mode)              │
├─────────────────────────────────────────────────────────────┤
│  Node 1              Node 2              Node 3            │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐   │
│  │ Controller  │     │ Controller  │     │ Controller  │   │
│  │ + Broker    │     │ + Broker    │     │ + Broker    │   │
│  │ Port 9093   │     │ Port 9093   │     │ Port 9093   │   │
│  │ Port 9092   │     │ Port 9092   │     │ Port 9092   │   │
│  └─────────────┘     └─────────────┘     └─────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Shared Cluster State                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Metadata Log (replicated across all controllers)   │   │
│  │ - Topic configurations                              │   │
│  │ - Partition assignments                             │   │
│  │ - Cluster membership                                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Network Flow

```
Client Applications
        │
        ▼
   Port 9092 (Broker API)
        │
        ▼
   Kafka Brokers ──► Port 9093 (Controller API) ──► KRaft Controllers
        │
        ▼
   Topic Data Storage
   (/kafka/logs or /tmp/kafka/logs)
```

### Directory Structure

**Development Layout:**
```
/tmp/kafka/logs/           # Data directory
/tmp/log/confluent/        # Application logs
/opt/kafka/                # Installation directory
```

**Production Layout:**
```
/kafka/logs/               # Data directory
/var/log/confluent/        # Application logs
/opt/kafka/                # Installation directory
```

## Best Practices

### Security

1. **User Isolation**
   - Run Kafka as dedicated `kafka` user
   - Minimal shell access (`/bin/false`)
   - Proper file permissions

2. **Network Security**
   - Firewall rules for ports 9092, 9093
   - SSH key-based authentication
   - Network segmentation

3. **Data Protection**
   - Regular backups of `/kafka/logs`
   - Monitor disk usage
   - Implement retention policies

### Performance

1. **Java Tuning**
   - Use G1GC for better latency
   - Appropriate heap sizing (1GB default)
   - GC logging for monitoring

2. **Kafka Configuration**
   - 24 partitions default for parallelism
   - Appropriate replication factor
   - Log retention based on requirements

3. **System Optimization**
   - Dedicated disks for Kafka data
   - Sufficient network bandwidth
   - Monitor system resources

### Operational

1. **Monitoring**
   - Log aggregation and analysis
   - JMX metrics collection
   - Health check automation

2. **Backup and Recovery**
   - Regular metadata backups
   - Disaster recovery procedures
   - Documentation maintenance

3. **Deployment Management**
   - Version control for scripts
   - Environment-specific configurations
   - Automated testing procedures

### Development Workflow

1. **Local Testing**
   - Use local deployment for development
   - Test configuration changes locally first
   - Validate scripts before production

2. **Environment Progression**
   - Development → Staging → Production
   - Configuration validation at each stage
   - Automated deployment pipelines

3. **Version Management**
   - Tag stable configurations
   - Document changes and rollback procedures
   - Maintain compatibility matrices

## Legacy Components

The following components are legacy and not used by current deployment scripts:

- `cluster-config.yaml.reference` - Example YAML configuration
- `cluster-config-local.yaml.reference` - Example local YAML configuration
- `build-kafka-ui.sh` - Kafka UI build script (removed)
- `download-kafka-ui.sh` - Kafka UI download script (removed)

These files are kept for reference but are not required for deployment.

## Support and Resources

### Official Documentation

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Confluent Platform Documentation](https://docs.confluent.io/)
- [KRaft Mode Documentation](https://kafka.apache.org/documentation/#kraft)

### Community Resources

- [Apache Kafka Users Mailing List](https://kafka.apache.org/contact)
- [Confluent Community Slack](https://confluentcommunity.slack.com/)
- [Stack Overflow - Apache Kafka](https://stackoverflow.com/questions/tagged/apache-kafka)

### Project Specific

For issues specific to this deployment project:

1. Check the troubleshooting section above
2. Review log files for detailed error messages
3. Verify prerequisites and file structure
4. Test with local deployment first

---

**Last Updated**: July 17, 2025  
**Version**: 2.0  
**Kafka Version**: Confluent Community 8.0.0  
**Java Version**: Oracle JDK 21.0.8 LTS
