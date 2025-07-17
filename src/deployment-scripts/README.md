# Kafka Deployment Scripts

This directory contains deployment scripts for Confluent Community Kafka 8.0.0 with KRaft mode.

## Files Overview

### Production Deployment
- `deplotail -f /var/ltail -f /var/log/confluent/kafka/kafka.log            # Production
tail -f /tmp/log/confluent/kafka/kafka.log           # Local
```

### Process Management
```bash
# Check processes
ps aux | grep kafka

# Kill processes (if needed)
sudo pkill -f kafka-server-start

# Restart services (Linux)
sudo systemctl restart kafka
```afka.log            # Production
tail -f /tmp/log/confluent/kafka/kafka.log           # Local
```

### Process Management
```bash
# Check processes
ps aux | grep kafka

# Kill processes (if needed)
sudo pkill -f kafka-server-start

# Restart services (Linux)
sudo systemctl restart kafka
```- Production deployment script for 3-server cluster
- `cluster-config.yaml` - Production YAML configuration (reference)

### Local Development
- `deploy-kafka-cluster-local.sh` - Local development deployment script for single-node
- `cluster-config-local.yaml` - Local YAML configuration (reference)

### Testing
- `test-kafka-simple.sh` - Simple Kafka connectivity test script

## Quick Start

### Local Development
```bash
# Run local deployment (requires sudo)
sudo ./deploy-kafka-cluster-local.sh

# Test deployment
./test-kafka-simple.sh
```

### Production Deployment
```bash
# Configure server IPs and credentials in the script
vim deploy-kafka-cluster.sh

# Run production deployment
./deploy-kafka-cluster.sh
```

## Prerequisites

### System Requirements
- **Linux Production**: RHEL 8 (or compatible)
- **macOS Development**: macOS with homebrew
- **Java**: Java 21 LTS (bundled in deployment files)
- **Memory**: Minimum 4GB RAM per node
- **Storage**: Minimum 50GB available space

### Network Requirements
- **Port 9092**: Kafka broker communication (plaintext)
- **Port 9093**: KRaft controller communication
- **SSH Access**: Passwordless SSH for production deployment

### Required Files
Place these files in `/Users/alexk/pipelines/kafka-community-8/deployment-files/`:
- `confluent-community-8.0.0.zip`
- `jdk-21.0.8.jdk/` (Java 21 JDK)

## Configuration

### Embedded Configuration
Both scripts now use embedded configuration instead of YAML parsing for reliability:

#### Production Script Configuration
```bash
# Server configuration
declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
declare -a IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")

# Update these values for your environment
SSH_USER="root"
SSH_KEY_PATH="/path/to/private/key"
```

#### Local Script Configuration
```bash
# Server configuration
declare -a HOSTNAMES=("localhost")
declare -a IPS=("127.0.0.1")

# Local deployment automatically uses current user
```

## Directory Structure

### Installation Paths
```
/opt/kafka/                     # Kafka installation
├── bin/                       # Executables (no .sh extensions)
├── etc/kafka/                 # Configuration files
├── lib/                       # Java libraries
└── share/                     # Shared resources
```

### Data and Logs
```
Production:
/kafka/logs/                   # Kafka data
/var/log/confluent/           # Application logs

Local Development:
/tmp/kafka/logs/              # Kafka data
/tmp/log/confluent/          # Application logs
```

## Platform Differences

### Linux (Production)
- Uses systemd services
- Standard user/group creation with `groupadd`/`useradd`
- Remote deployment via SSH

### macOS (Development)
- Manual process startup (no systemd)
- User/group creation with `dscl` commands
- Local deployment only

## Known Issues

### Java Version Compatibility
- **Java 21+**: Contains deprecated JVM options (`PrintGCDateStamps`)
- **Solution**: Use Java 8 or Java 11 LTS
- **Symptoms**: `Unrecognized VM option 'PrintGCDateStamps'` error

### Directory Permissions
- **Issue**: Permission denied errors during installation
- **Solution**: Run scripts with `sudo` privileges
- **macOS Specific**: May require additional permission handling

### File Extraction
- **Issue**: Confluent ZIP extracts as `confluent-8.0.0/` directory
- **Solution**: Scripts automatically rename to `kafka/`
- **Binary Names**: Use `kafka-server-start` not `kafka-server-start.sh`

## Testing and Verification

### Manual Testing
```bash
# Check if Kafka is running
ps aux | grep kafka | grep -v grep

# Test API connectivity
/opt/kafka/bin/kafka-broker-api-versions --bootstrap-server localhost:9092

# Create test topic
/opt/kafka/bin/kafka-topics --create --topic test --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1

# List topics
/opt/kafka/bin/kafka-topics --list --bootstrap-server localhost:9092
```

### Automated Testing
```bash
# Use the test script
./test-kafka-simple.sh
```

## Troubleshooting

### Common Errors

#### "kafka: illegal group name"
- **Cause**: Group creation failed
- **Solution**: Check platform-specific user/group creation commands

#### "No such file or directory: kafka-storage.sh"
- **Cause**: Script references include .sh extensions
- **Solution**: Use `kafka-storage` without .sh extension

#### "PrintGCDateStamps" JVM Error
- **Cause**: Java version 17+ incompatibility
- **Solution**: Install Java 8 or Java 11

#### Permission Denied
- **Cause**: Insufficient privileges
- **Solution**: Run with `sudo` and check file ownership

### Log Locations
```bash
# Kafka logs
tail -f /var/log/confluent/kafka/server.log          # Production
tail -f /tmp/log/confluent/kafka/kafka.log           # Local

# Kafka UI logs
tail -f /var/log/confluent/provectus-kafka-ui/application.log
```

### Process Management
```bash
# Check processes
ps aux | grep kafka

# Kill processes (if needed)
sudo pkill -f kafka-server-start
sudo pkill -f kafka-ui

# Restart services (Linux)
sudo systemctl restart kafka
sudo systemctl restart kafka-ui
```

## Security Considerations

### User Permissions
- Kafka runs as system user `kafka:kafka`
- Minimal privileges (no shell access)
- Proper file ownership and permissions

### Network Security
- Currently uses plaintext communication
- Suitable for development and trusted networks
- Production should implement SSL/SASL authentication

### File Security
- Configuration files contain sensitive information
- Restrict access to deployment scripts
- Use SSH key-based authentication for production

## Architecture Overview

### KRaft Mode (No Zookeeper)
- Each node acts as controller + broker
- Quorum-based consensus for metadata
- Simplified deployment and management
- Better performance and reliability

### High Availability
- 3-node production cluster (minimum)
- Replication factor 3 for data durability
- Automatic leader election
- Fault tolerance for single node failures

### Monitoring
- Standard Kafka JMX metrics available
- Log aggregation for troubleshooting
- Command-line tools for cluster management
