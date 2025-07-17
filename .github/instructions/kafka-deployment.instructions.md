---
applyTo: '**/*.sh,**/*.yaml'
---

# Kafka Deployment Instructions

This document provides coding guidelines and project context for AI when generating, modifying, or reviewing Kafka deployment scripts and YAML configurations.

## Project Context

This project contains deployment scripts and configurations for Confluent Community Kafka clusters using KRaft mode (Kafka without Zookeeper). The deployment supports both local development and production environments.

## Shell Script Requirements

### Environment Configuration
- **MUST** prompt user for environment name at script start
- **MUST** prompt user for number of servers (minimum 1)
- **MUST** validate environment name (alphanumeric characters only, no spaces)
- **MUST** validate server count (minimum 1, maximum defined in config)
- **MUST** use environment name in all cluster/node naming conventions
- **MUST** export environment variables for use throughout the script

### Distribution and Installation
- **MUST** use `confluent-community-8.0.0.zip` as the source distribution
- **MUST** support offline/air-gapped deployment from local files
- **MUST** install to `/opt/kafka` directory structure
- **MUST** create `kafka` user/group with minimal privileges
- **MUST** verify file integrity before extraction

### Cluster Architecture
- **MUST** deploy N-node KRaft cluster based on user input (controller + broker on each node)
- **MUST** use standard ports: 9092 (plaintext), 9093 (controller)
- **MUST** configure quorum voters with environment-specific hostnames
- **MUST** disable auto topic creation (`auto.create.topics.enable=false`)
- **MUST** support single-node deployment for development environments
- **MUST** generate unique cluster UUID for KRaft initialization

### Directory Structure and Permissions
- **MUST** create `/kafka/logs` for data storage
- **MUST** create `/var/log/confluent` for application logs
- **MUST** set proper ownership (`kafka:kafka`) on all Kafka directories
- **MUST** create separate directories for each topic partition
- **MUST** ensure proper file permissions for security

### Service Configuration
- **MUST** create systemd services for `kafka`
- **MUST** configure automatic restart on failure (`Restart=on-abnormal`)
- **MUST** use environment variables in service configurations
- **MUST** configure proper service dependencies and ordering

### Performance and Reliability Settings
- **MUST** configure 24 partitions as default
- **MUST** set replication factor to 3 (or server count if less than 3)
- **MUST** set `min.insync.replicas=2` (or 1 for single-node)
- **MUST** configure 24-hour log retention (`log.retention.ms=86400000`)
- **MUST** set appropriate buffer sizes and thread counts

### Validation and Health Checks
- **MUST** verify OS compatibility (RHEL 8 for production)
- **MUST** test SSH connectivity to all nodes before deployment
- **MUST** validate cluster formation after deployment
- **MUST** verify all services are running and healthy
- **MUST** test broker API connectivity post-deployment

### Error Handling and Logging
- **MUST** validate all prerequisites before deployment starts
- **MUST** provide clear error messages with remediation steps
- **MUST** implement proper exit codes for automation
- **MUST** log all operations for troubleshooting
- **MUST** use `set -e` for immediate exit on errors

## Platform-Specific Requirements

### Linux (Production) Deployment
- **MUST** use `groupadd -r` and `useradd -r` for system user creation
- **MUST** validate user/group creation with `getent group` and `id` commands
- **MUST** use systemd services for process management
- **MUST** create `/etc/systemd/system/kafka.service`
- **MUST** use `systemctl daemon-reload`, `systemctl enable`, and `systemctl start`

### macOS (Development) Deployment
- **MUST** use `dscl` commands for user and group creation
- **MUST** validate with `dscl . -read /Groups/kafka` and `dscl . -read /Users/kafka`
- **MUST** use manual process startup or launchd (not systemd)
- **MUST** handle directory permission issues with appropriate `sudo` usage

## File Path and Binary Requirements

### Confluent Community 8.0.0 Structure
- **MUST** use `/opt/kafka/etc/kafka/server.properties` (NOT `/opt/kafka/config/kraft/`)
- **MUST** reference binaries without `.sh` extensions (e.g., `kafka-server-start`, not `kafka-server-start.sh`)
- **MUST** extract `confluent-8.0.0.zip` and rename `confluent-8.0.0/` to `kafka/`
- **MUST** handle case where extraction creates nested directory structure

### Binary References
- **MUST** use `/opt/kafka/bin/kafka-storage` (not `kafka-storage.sh`)
- **MUST** use `/opt/kafka/bin/kafka-server-start` (not `kafka-server-start.sh`)
- **MUST** use `/opt/kafka/bin/kafka-server-stop` (not `kafka-server-stop.sh`)
- **MUST** use `/opt/kafka/bin/kafka-topics` for topic management
- **MUST** use `/opt/kafka/bin/kafka-broker-api-versions` for connectivity testing

## Java Version Compatibility

### Supported Versions
- **MUST** use Java 8 or Java 11 LTS for production deployments
- **MUST** validate Java version compatibility before installation
- **MUST** document Java version requirements in deployment guides

### Known Issues
- **MUST** avoid Java 17+ due to deprecated JVM options in Kafka startup scripts
- **MUST** handle `PrintGCDateStamps` deprecation in Java 9+
- **MUST** provide alternative JVM configurations for newer Java versions if required

## Configuration Embedded in Scripts

### Shell-Based Configuration (Recommended)
- **MUST** embed all configuration directly in shell scripts for reliability
- **MUST** use shell arrays and variables instead of external YAML parsing
- **MUST** separate production and local deployment scripts with different embedded configs
- **MUST** avoid complex YAML parsing in shell scripts due to error-prone nature

## YAML Configuration Requirements (Legacy)

### File Structure
- **MUST** validate YAML configuration file exists before parsing
- **MUST** parse server IPs and credentials from YAML
- **MUST** support SSH key-based authentication
- **MUST** allow customization of ports and directories
- **MUST** support `${ENVIRONMENT}` substitution in YAML values

### Configuration Parameters
- **MUST** define cluster name with environment substitution
- **MUST** specify cluster version (8.0.0)
- **MUST** configure server hostnames and IP addresses
- **MUST** define SSH user and Kafka user/group
- **MUST** specify ports for plaintext and controller listeners
- **MUST** configure data and log directories
- **MUST** specify maximum servers limit

### Security Configuration
- **MUST** use minimal privilege principles for service accounts
- **MUST** configure proper file permissions and ownership
- **MUST** support secure communication protocols
- **MUST** validate SSH access before deployment

## Local vs Production Deployment

### Local Deployment
- **MUST** skip SSH connectivity tests
- **MUST** skip OS verification
- **MUST** use local file paths instead of remote copying
- **MUST** support localhost-only configuration
- **MUST** allow running with current user privileges

### Production Deployment
- **MUST** verify RHEL 8 operating system
- **MUST** test SSH connectivity to all nodes
- **MUST** copy installation files to remote nodes
- **MUST** create proper service users and permissions
- **MUST** configure network communication between nodes

## Code Style and Best Practices

### Script Structure
- Use clear function definitions with descriptive names
- Implement proper parameter validation
- Use meaningful variable names with consistent naming conventions
- Include comprehensive error handling with informative messages
- Add comments explaining complex logic or business rules

### YAML Processing
- Use robust YAML parsing that handles edge cases
- Validate required fields before processing
- Support both quoted and unquoted values
- Handle environment variable substitution safely

### Security Considerations
- Never log or display sensitive information (passwords, keys)
- Validate all user inputs to prevent injection attacks
- Use secure file permissions for configuration files
- Implement proper privilege separation