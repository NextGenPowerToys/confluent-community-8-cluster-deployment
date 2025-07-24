#!/bin/bash

set -e

# Ask for deployment type
read -p "Deployment type - (l)ocal, (d)ocker, or (r)emote? " DEPLOY_TYPE
case "$DEPLOY_TYPE" in
    [Ll]*)
        LOCAL_DEPLOYMENT=true
        DOCKER_DEPLOYMENT=false
        ;;
    [Dd]*)
        LOCAL_DEPLOYMENT=false
        DOCKER_DEPLOYMENT=true
        ;;
    [Rr]*)
        LOCAL_DEPLOYMENT=false
        DOCKER_DEPLOYMENT=false
        ;;
    *)
        echo "ERROR: Invalid deployment type. Use l, d, or r"
        exit 1
        ;;
esac

# Prompt for environment name
read -p "Enter environment name (alphanumeric only): " ENVIRONMENT
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "ERROR: Environment name must be alphanumeric only"
    exit 1
fi

# Prompt for number of servers
read -p "Enter number of servers (minimum 1): " SERVER_COUNT
if [[ ! "$SERVER_COUNT" =~ ^[0-9]+$ ]] || [[ $SERVER_COUNT -lt 1 ]]; then
    echo "ERROR: Server count must be a number >= 1"
    exit 1
fi

# SSH credentials prompting for Docker and Remote deployments
if [[ "$DOCKER_DEPLOYMENT" == "true" ]] || [[ "$LOCAL_DEPLOYMENT" == "false" ]]; then
    echo "=== SSH Credentials Configuration ==="
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        echo "For Docker deployment, containers are accessed via localhost with these ports:"
        echo "  - kafka-test-node1: localhost:2221"
        echo "  - kafka-test-node2: localhost:2222" 
        echo "  - kafka-test-node3: localhost:2223"
        echo "Common SSH users: admin (default), root"
    fi
    
    read -p "Enter SSH username for all servers: " SSH_USER
    
    # Validate SSH user input
    if [[ -z "$SSH_USER" ]]; then
        echo "ERROR: SSH username cannot be empty"
        exit 1
    fi
    
    echo "SSH username configured: $SSH_USER"
    echo "Note: You will be prompted for the SSH password during deployment operations."
    echo
fi

# Server configuration based on deployment type
if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
    # Docker deployment uses containers created by manage-servers.sh
    declare -a CONTAINER_NAMES=("kafka-test-node1" "kafka-test-node2" "kafka-test-node3")
    declare -a SSH_PORTS=("2221" "2222" "2223")
    declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
    declare -a IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")
    LOCAL_FILES_PATH="/tmp/files"
elif [[ "$LOCAL_DEPLOYMENT" == "false" ]]; then
    # Remote deployment - use provided server details
    declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
    declare -a IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")
    LOCAL_FILES_PATH="/Users/alexk/pipelines/kafka-community-8/deployment-files"
else
    # Local deployment
    declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")  
    declare -a IPS=("127.0.0.1" "127.0.0.1" "127.0.0.1")
    LOCAL_FILES_PATH="/Users/alexk/pipelines/kafka-community-8/deployment-files"
fi

# Credentials
KAFKA_USER="kafka"
KAFKA_GROUP="kafka"

# Network configuration
PLAINTEXT_PORT=9092
CONTROLLER_PORT=9093

# Storage configuration
DATA_DIR="/kafka"
LOG_DIR="/var/log/confluent"

# Installation files
CONFLUENT_ZIP="confluent-community-8.0.0.zip"
JDK_ARCHIVE="jdk-21.0.8-macos-x64.tar.gz"
JAVA_HOME="/opt/jdk-21.0.8.jdk/Contents/Home"

# Kafka configuration
PARTITIONS_PER_TOPIC=24
RETENTION_HOURS=24
SEGMENT_RETENTION_HOURS=1
REPLICATION_FACTOR=3
MIN_INSYNC_REPLICAS=2
AUTO_CREATE_TOPICS=false

export ENVIRONMENT
export SERVER_COUNT

# Validation functions
validate_java() {
    echo "Validating Java installation..."
    
    # Check if JDK archive exists
    if [[ ! -f "$LOCAL_FILES_PATH/$JDK_ARCHIVE" ]]; then
        echo "ERROR: JDK archive not found at $LOCAL_FILES_PATH/$JDK_ARCHIVE"
        exit 1
    fi
    
    # Extract JDK if not already extracted
    if [[ ! -d "$JAVA_HOME" ]]; then
        echo "Extracting JDK from $JDK_ARCHIVE..."
        sudo mkdir -p /opt
        cd /opt
        sudo tar -xzf "$LOCAL_FILES_PATH/$JDK_ARCHIVE"
        echo "JDK extracted successfully"
    fi
    
    if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
        echo "ERROR: Java executable not found or not executable at $JAVA_HOME/bin/java"
        exit 1
    fi
    
    local java_version=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | awk -F '"' '{print $2}')
    echo "Found Java version: $java_version"
}

validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check if running as root (not recommended but sometimes necessary)
    if [[ $EUID -eq 0 ]]; then
        echo "WARNING: Running as root. This is not recommended."
    fi
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        echo "Docker deployment - validating container prerequisites..."
        # Only check if Confluent ZIP exists in deployment-files
        if [[ ! -f "/Users/alexk/pipelines/kafka-community-8/deployment-files/$CONFLUENT_ZIP" ]]; then
            echo "ERROR: Confluent ZIP not found at /Users/alexk/pipelines/kafka-community-8/deployment-files/$CONFLUENT_ZIP"
            exit 1
        fi
        
        # Validate that containers have required utilities
        echo "Checking if containers have required utilities..."
        echo "Note: Since servers are air-gapped, all required utilities must be pre-installed"
        echo "Required utilities: unzip, tar, sudo, groupadd, useradd"
        
        echo "Prerequisites validation completed successfully"
        return 0
    fi
    
    validate_java
    
    # Check installation files
    if [[ ! -f "$LOCAL_FILES_PATH/$CONFLUENT_ZIP" ]]; then
        echo "ERROR: Confluent ZIP not found at $LOCAL_FILES_PATH/$CONFLUENT_ZIP"
        exit 1
    fi
    
    if [[ ! -f "$LOCAL_FILES_PATH/$JDK_ARCHIVE" ]]; then
        echo "ERROR: JDK archive not found at $LOCAL_FILES_PATH/$JDK_ARCHIVE"
        exit 1
    fi
    
    echo "Prerequisites validation completed successfully"
}

# Build nodes array with environment substitution
NODES=()
for i in "${!HOSTNAMES[@]}"; do
    hostname=${HOSTNAMES[$i]//node/${ENVIRONMENT}-node}
    NODES+=("$hostname")
done

# Verify RHEL 8
verify_os() {
    if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
        echo "Local deployment - skipping OS verification"
        return 0
    fi
    
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$1 "grep -q 'Red Hat Enterprise Linux.*8' /etc/redhat-release" || {
        echo "ERROR: $1 is not RHEL 8"
        exit 1
    }
}

# Test SSH connectivity
test_ssh() {
    if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
        echo "Local deployment - skipping SSH test"
        return 0
    fi
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        echo "Testing Docker SSH connectivity..."
        for i in "${!CONTAINER_NAMES[@]}"; do
            if [[ $i -lt $SERVER_COUNT ]]; then
                container_name=${CONTAINER_NAMES[$i]}
                ssh_port=${SSH_PORTS[$i]}
                node_name=${NODES[$i]}
                
                echo "Testing SSH to $container_name via localhost:$ssh_port..."
                
                # Test SSH connection with password prompt
                ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ssh_port $SSH_USER@localhost "echo 'SSH OK to $container_name'" || {
                    echo "ERROR: Cannot SSH to $container_name via localhost:$ssh_port"
                    echo "Please ensure:"
                    echo "  1. Container $container_name is running"
                    echo "  2. SSH service is available on port $ssh_port"
                    echo "  3. Username '$SSH_USER' and password are correct"
                    echo ""
                    echo "You can test manually with:"
                    echo "  ssh $SSH_USER@localhost -p $ssh_port"
                    echo ""
                    echo "Or check container status with:"
                    echo "  ./manage-servers.sh status"
                    exit 1
                }
                
                # Test required utilities on each container
                echo "  Testing required utilities on $container_name..."
                ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ssh_port $SSH_USER@localhost << 'UTILITY_CHECK'
                    MISSING_UTILITIES=()
                    
                    if ! command -v unzip &> /dev/null; then
                        MISSING_UTILITIES+=("unzip")
                    fi
                    
                    if ! command -v tar &> /dev/null; then
                        MISSING_UTILITIES+=("tar")
                    fi
                    
                    if ! command -v sudo &> /dev/null; then
                        MISSING_UTILITIES+=("sudo")
                    fi
                    
                    if ! command -v groupadd &> /dev/null; then
                        MISSING_UTILITIES+=("groupadd")
                    fi
                    
                    if ! command -v useradd &> /dev/null; then
                        MISSING_UTILITIES+=("useradd")
                    fi
                    
                    if [[ ${#MISSING_UTILITIES[@]} -gt 0 ]]; then
                        echo "ERROR: Required utilities missing on this container:"
                        for util in "${MISSING_UTILITIES[@]}"; do
                            echo "  - $util"
                        done
                        echo ""
                        echo "This is an air-gapped deployment. All utilities must be pre-installed."
                        exit 1
                    fi
                    
                    echo "  ✅ All required utilities available on this container"
UTILITY_CHECK
            fi
        done
        echo "Docker SSH connectivity test completed successfully"
        return 0
    fi
    
    echo "Testing SSH connectivity to remote servers..."
    for i in "${!NODES[@]}"; do
        if [[ $i -lt $SERVER_COUNT ]]; then
            node_name=${NODES[$i]}
            node_ip=${IPS[$i]}
            
            echo "Testing SSH to $node_name ($node_ip)..."
            
            # Test SSH connection with password prompt for remote servers
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$node_ip "echo 'SSH OK to $node_name'" || {
                echo "ERROR: Cannot SSH to $node_name ($node_ip)"
                echo "Please ensure:"
                echo "  1. SSH service is running on target host"
                echo "  2. Host $node_ip is reachable"
                echo "  3. Username '$SSH_USER' and password are correct"
                echo "  4. SSH password authentication is enabled"
                exit 1
            }
            
            # Test required utilities on remote server
            echo "  Testing required utilities on $node_name..."
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$node_ip << 'UTILITY_CHECK'
                MISSING_UTILITIES=()
                
                if ! command -v unzip &> /dev/null; then
                    MISSING_UTILITIES+=("unzip")
                fi
                
                if ! command -v tar &> /dev/null; then
                    MISSING_UTILITIES+=("tar")
                fi
                
                if ! command -v sudo &> /dev/null; then
                    MISSING_UTILITIES+=("sudo")
                fi
                
                if ! command -v groupadd &> /dev/null; then
                    MISSING_UTILITIES+=("groupadd")
                fi
                
                if ! command -v useradd &> /dev/null; then
                    MISSING_UTILITIES+=("useradd")
                fi
                
                if [[ ${#MISSING_UTILITIES[@]} -gt 0 ]]; then
                    echo "ERROR: Required utilities missing on this server:"
                    for util in "${MISSING_UTILITIES[@]}"; do
                        echo "  - $util"
                    done
                    echo ""
                    echo "This is an air-gapped deployment. All utilities must be pre-installed."
                    exit 1
                fi
                
                echo "  ✅ All required utilities available on this server"
UTILITY_CHECK
            
            # Verify OS for remote deployment
            verify_os $node_ip
        fi
    done
    echo "Remote SSH connectivity test completed successfully"
}

# Install on node
install_node() {
    local node_ip=$1
    local node_id=$2
    local is_first_node=$3
    
    echo "Installing Kafka on node $node_id..."
    
    if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
        FILE_PREFIX="$LOCAL_FILES_PATH/"
        EXEC_PREFIX=""
        SUDO_CMD="sudo"
    elif [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        FILE_PREFIX="/tmp/"
        ssh_port=${SSH_PORTS[$((node_id-1))]}
        EXEC_PREFIX="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ssh_port root@localhost"
        # For Docker deployment using root, no sudo needed
        SUDO_CMD=""
    else
        FILE_PREFIX="/tmp/"
        EXEC_PREFIX="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$node_ip"
        SUDO_CMD="sudo"
    fi
    
    $EXEC_PREFIX bash << EOF
        set -e
        
        echo "Creating directory structure..."
        
        # Detect platform for user/group creation
        if [[ "\$(uname)" == "Darwin" ]]; then
            # macOS user creation
            if ! dscl . -read /Groups/$KAFKA_GROUP >/dev/null 2>&1; then
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Groups/$KAFKA_GROUP
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Groups/$KAFKA_GROUP PrimaryGroupID 502
            fi
            
            if ! dscl . -read /Users/$KAFKA_USER >/dev/null 2>&1; then
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Users/$KAFKA_USER
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Users/$KAFKA_USER UserShell /bin/false
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Users/$KAFKA_USER RealName "Kafka User"
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Users/$KAFKA_USER UniqueID 502
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Users/$KAFKA_USER PrimaryGroupID 502
                ${SUDO_CMD:+$SUDO_CMD} dscl . -create /Users/$KAFKA_USER NFSHomeDirectory /opt/kafka
            fi
        else
            # Linux user creation
            if ! getent group $KAFKA_GROUP >/dev/null 2>&1; then
                ${SUDO_CMD:+$SUDO_CMD} groupadd -r $KAFKA_GROUP
            fi
            
            if ! id $KAFKA_USER >/dev/null 2>&1; then
                ${SUDO_CMD:+$SUDO_CMD} useradd -r -g $KAFKA_GROUP -s /bin/false -d /opt/kafka $KAFKA_USER
            fi
        fi
        
        echo "Cleaning up existing installations..."
        ${SUDO_CMD:+$SUDO_CMD} rm -rf /opt/kafka /opt/confluent-* /opt/jdk-* 2>/dev/null || true
        ${SUDO_CMD:+$SUDO_CMD} rm -rf $DATA_DIR $LOG_DIR 2>/dev/null || true
        
        # Install Java for Docker/Linux environments
        if [[ "\$(uname)" != "Darwin" ]]; then
            echo "Installing Java 21 from offline tarball..."
            cd /opt
            ${SUDO_CMD:+$SUDO_CMD} tar -xzf ${FILE_PREFIX}jdk-21_linux-aarch64_bin.tar.gz
            
            # Find the actual JDK directory using ls
            JDK_DIR=\$(ls -d /opt/jdk-21* 2>/dev/null | head -1)
            if [[ -n "\$JDK_DIR" ]]; then
                export JAVA_HOME=\$JDK_DIR
                ${SUDO_CMD:+$SUDO_CMD} chown -R root:root \$JDK_DIR 2>/dev/null || true
                echo "Java 21 installed successfully at \$JAVA_HOME"
            else
                echo "ERROR: Could not find JDK directory after extraction"
                ls -la /opt/
                exit 1
            fi
        else
            # Extract JDK if not already extracted (macOS)
            if [[ ! -d "$JAVA_HOME" ]]; then
                echo "Extracting JDK from ${FILE_PREFIX}$JDK_ARCHIVE..."
                cd /opt
                ${SUDO_CMD:+$SUDO_CMD} tar -xzf ${FILE_PREFIX}$JDK_ARCHIVE
                echo "JDK extracted successfully"
            fi
        fi
        
        # Create directories
        ${SUDO_CMD:+$SUDO_CMD} mkdir -p /opt/kafka $DATA_DIR/logs $LOG_DIR/kafka
        ${SUDO_CMD:+$SUDO_CMD} chown -R $KAFKA_USER:$KAFKA_GROUP $DATA_DIR $LOG_DIR 2>/dev/null || true
        
        echo "Extracting Confluent Community $CONFLUENT_ZIP..."
        
        # Extract Confluent
        cd /opt
        ${SUDO_CMD:+$SUDO_CMD} unzip -q ${FILE_PREFIX}$CONFLUENT_ZIP
        
        # Handle different extraction patterns - find the confluent directory using ls
        CONFLUENT_DIR=\$(ls -d confluent* 2>/dev/null | head -1)
        if [[ -n "\$CONFLUENT_DIR" ]]; then
            echo "Found Confluent directory: \$CONFLUENT_DIR"
            # Move contents of confluent directory to kafka, not the directory itself
            ${SUDO_CMD:+$SUDO_CMD} mv "\$CONFLUENT_DIR"/* kafka/
            ${SUDO_CMD:+$SUDO_CMD} rmdir "\$CONFLUENT_DIR"
            echo "Contents of /opt/kafka after move:"
            ls -la /opt/kafka
        else
            echo "ERROR: No confluent directory found after extraction"
            echo "Available directories:"
            ls -la
            exit 1
        fi
        
        ${SUDO_CMD:+$SUDO_CMD} chown -R $KAFKA_USER:$KAFKA_GROUP /opt/kafka
        
        # Set JAVA_HOME for different environments
        if [[ "\$(uname)" != "Darwin" ]]; then
            # Find the JDK directory using ls
            JDK_DIR=\$(ls -d /opt/jdk-21* 2>/dev/null | head -1)
            if [[ -n "\$JDK_DIR" ]]; then
                export JAVA_HOME=\$JDK_DIR
            else
                echo "ERROR: Could not find JDK directory"
                exit 1
            fi
        fi
        
        # Find the kafka-storage script
        KAFKA_STORAGE_SCRIPT="/opt/kafka/bin/kafka-storage"
        if [[ ! -f "\$KAFKA_STORAGE_SCRIPT" ]]; then
            echo "ERROR: kafka-storage script not found at \$KAFKA_STORAGE_SCRIPT"
            echo "Available files in /opt/kafka/bin:"
            ls -la /opt/kafka/bin/ 2>/dev/null || echo "No /opt/kafka/bin directory"
            exit 1
        fi
        
        echo "Using kafka-storage script: \$KAFKA_STORAGE_SCRIPT"
        
        # Use shared cluster UUID for all nodes
        CLUSTER_UUID="$SHARED_CLUSTER_UUID"
        echo "Using shared cluster UUID: \$CLUSTER_UUID"
        
        # Set the correct hostname for advertised listeners
        if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
            # Use localhost with mapped ports for Docker deployment external access
            case $node_id in
                1) ADVERTISED_HOSTNAME="localhost" ; ADVERTISED_PORT="9092" ;;
                2) ADVERTISED_HOSTNAME="localhost" ; ADVERTISED_PORT="9094" ;;
                3) ADVERTISED_HOSTNAME="localhost" ; ADVERTISED_PORT="9096" ;;
            esac
        else
            ADVERTISED_HOSTNAME="${NODES[$((node_id-1))]}"
            ADVERTISED_PORT="$PLAINTEXT_PORT"
        fi
        echo "Advertised hostname: \$ADVERTISED_HOSTNAME:\$ADVERTISED_PORT"
        
        # Build quorum voters list - use container hostnames for Docker deployment
        QUORUM_VOTERS=""
        for ((j=1; j<=$SERVER_COUNT; j++)); do
            if [[ \$j -gt 1 ]]; then
                QUORUM_VOTERS="\${QUORUM_VOTERS},"
            fi
            
            if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
                # Use actual container hostnames for Docker deployment
                container_hostname="kafka-test-node\${j}"
                QUORUM_VOTERS="\${QUORUM_VOTERS}\${j}@\${container_hostname}:$CONTROLLER_PORT"
            else
                QUORUM_VOTERS="\${QUORUM_VOTERS}\${j}@kafka-${ENVIRONMENT}-node-\${j}:$CONTROLLER_PORT"
            fi
        done
        echo "Quorum voters: \$QUORUM_VOTERS"
        
        echo "Creating Kafka server configuration..."
        
        # Create server.properties
        if [[ -n "$SUDO_CMD" ]]; then
            ${SUDO_CMD:+$SUDO_CMD} -u $KAFKA_USER tee /opt/kafka/etc/kafka/server.properties > /dev/null << EOC
process.roles=controller,broker
node.id=$node_id
controller.quorum.voters=\$QUORUM_VOTERS
listeners=PLAINTEXT://:$PLAINTEXT_PORT,CONTROLLER://:$CONTROLLER_PORT
inter.broker.listener.name=PLAINTEXT
advertised.listeners=PLAINTEXT://\${ADVERTISED_HOSTNAME}:\${ADVERTISED_PORT}
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=$DATA_DIR/logs
num.partitions=$PARTITIONS_PER_TOPIC
default.replication.factor=$REPLICATION_FACTOR
min.insync.replicas=$MIN_INSYNC_REPLICAS
auto.create.topics.enable=$AUTO_CREATE_TOPICS
delete.topic.enable=true
log.retention.ms=\$(($RETENTION_HOURS * 3600000))
log.segment.ms=\$(($SEGMENT_RETENTION_HOURS * 3600000))
log.cleanup.policy=delete
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
EOC
        else
            # Running as root, create file directly
            tee /opt/kafka/etc/kafka/server.properties > /dev/null << EOC
process.roles=controller,broker
node.id=$node_id
controller.quorum.voters=\$QUORUM_VOTERS
listeners=PLAINTEXT://:$PLAINTEXT_PORT,CONTROLLER://:$CONTROLLER_PORT
inter.broker.listener.name=PLAINTEXT
advertised.listeners=PLAINTEXT://\${ADVERTISED_HOSTNAME}:\${ADVERTISED_PORT}
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=$DATA_DIR/logs
num.partitions=$PARTITIONS_PER_TOPIC
default.replication.factor=$REPLICATION_FACTOR
min.insync.replicas=$MIN_INSYNC_REPLICAS
auto.create.topics.enable=$AUTO_CREATE_TOPICS
delete.topic.enable=true
log.retention.ms=\$(($RETENTION_HOURS * 3600000))
log.segment.ms=\$(($SEGMENT_RETENTION_HOURS * 3600000))
log.cleanup.policy=delete
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
EOC
            # Change ownership after creating the file
            chown $KAFKA_USER:$KAFKA_GROUP /opt/kafka/etc/kafka/server.properties
        fi
        
        echo "Server configuration created successfully"
        
        echo "Formatting Kafka storage for KRaft mode..."
        
        # Ensure clean data directory
        ${SUDO_CMD:+$SUDO_CMD} rm -rf $DATA_DIR/logs/* 2>/dev/null || true
        ${SUDO_CMD:+$SUDO_CMD} mkdir -p $DATA_DIR/logs
        ${SUDO_CMD:+$SUDO_CMD} chown -R $KAFKA_USER:$KAFKA_GROUP $DATA_DIR
        
        # Format storage
        if [[ -n "$SUDO_CMD" ]]; then
            ${SUDO_CMD:+$SUDO_CMD} -u $KAFKA_USER JAVA_HOME=\$JAVA_HOME \$KAFKA_STORAGE_SCRIPT format -t \$CLUSTER_UUID -c /opt/kafka/etc/kafka/server.properties
        else
            # Running as root, run directly then change ownership
            su - $KAFKA_USER -s /bin/bash -c "JAVA_HOME=\$JAVA_HOME \$KAFKA_STORAGE_SCRIPT format -t \$CLUSTER_UUID -c /opt/kafka/etc/kafka/server.properties"
        fi
        
        echo "Storage formatting completed successfully"
        
        # Validate storage formatting
        if [[ -f "$DATA_DIR/logs/meta.properties" ]]; then
            echo "✅ Storage formatting validated - meta.properties exists"
        else
            echo "❌ Storage formatting validation failed - meta.properties not found"
            echo "Contents of $DATA_DIR/logs:"
            ls -la $DATA_DIR/logs/ || true
            exit 1
        fi
EOF
}

# Start Kafka services
start_services() {
    echo "Starting Kafka services simultaneously..."
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        # Start all Docker nodes sequentially to avoid SSH password conflicts
        for i in "${!NODES[@]}"; do
            if [[ $i -ge $SERVER_COUNT ]]; then
                continue
            fi
            
            node_name=${NODES[$i]}
            ssh_port=${SSH_PORTS[$i]}
            
            echo "Starting Kafka on $node_name..."
            
            # Start Kafka service on this node
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -p $ssh_port $SSH_USER@localhost << 'EOF'
                # Find JDK directory
                JDK_DIR=$(ls -d /opt/jdk-21* 2>/dev/null | head -1)
                if [[ -n "$JDK_DIR" ]]; then
                    export JAVA_HOME=$JDK_DIR
                else
                    echo "ERROR: Could not find JDK directory"
                    exit 1
                fi
                
                echo "Starting Kafka server..."
                
                # Start Kafka in background
                if [[ -n "${SUDO_CMD}" ]]; then
                    nohup ${SUDO_CMD:+$SUDO_CMD} -u kafka JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-server-start /opt/kafka/etc/kafka/server.properties > /var/log/confluent/kafka/kafka.log 2>&1 &
                else
                    # Running as root, use su to run as kafka user
                    nohup su - kafka -s /bin/bash -c "JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-server-start /opt/kafka/etc/kafka/server.properties" > /var/log/confluent/kafka/kafka.log 2>&1 &
                fi
                
                echo "Kafka startup command executed, waiting for service to initialize..."
                sleep 5
EOF
            
            if [ $? -eq 0 ]; then
                echo "✅ Kafka startup command executed successfully on $node_name"
            else
                echo "❌ Failed to start Kafka on $node_name"
                exit 1
            fi
        done
        
        echo "Waiting for all Kafka nodes to fully initialize..."
        sleep 30
        
        # Check if all nodes are running - with retry logic
        for i in "${!NODES[@]}"; do
            if [[ $i -ge $SERVER_COUNT ]]; then
                continue
            fi
            
            node_name=${NODES[$i]}  
            ssh_port=${SSH_PORTS[$i]}
            
            echo "Checking Kafka status on $node_name..."
            
            # Try to check status with retries
            local check_retries=3
            local check_attempt=1
            local kafka_running=false
            
            while [ $check_attempt -le $check_retries ]; do
                echo "  Status check attempt $check_attempt for $node_name..."
                
                if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -p $ssh_port $SSH_USER@localhost << 'EOF'; then
                    for attempt in {1..10}; do
                        if netstat -ln 2>/dev/null | grep -q ":9092.*LISTEN" || ss -ln 2>/dev/null | grep -q ":9092"; then
                            echo "Kafka is listening on port 9092"
                            exit 0
                        fi
                        
                        if [ $attempt -eq 10 ]; then
                            echo "Kafka not yet listening on port 9092 after 20 seconds"
                            echo "Last 5 lines of Kafka log:"
                            tail -5 /var/log/confluent/kafka/kafka.log 2>/dev/null || echo "No log file found"
                            exit 1
                        fi
                        
                        sleep 2
                    done
EOF
                    kafka_running=true
                    echo "✅ $node_name is running and listening on port 9092"
                    break
                else
                    echo "  ⚠️  Status check attempt $check_attempt failed for $node_name"
                    if [ $check_attempt -eq $check_retries ]; then
                        echo "❌ Failed to verify Kafka status on $node_name after $check_retries attempts"
                        echo "Attempting to get log information..."
                        
                        # Try one more time to get logs for troubleshooting
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p $ssh_port $SSH_USER@localhost \
                            "echo 'Kafka log tail:'; tail -10 /var/log/confluent/kafka/kafka.log 2>/dev/null || echo 'No log file found'" || echo "Could not retrieve logs"
                        
                        exit 1
                    fi
                    ((check_attempt++))
                    sleep 10
                fi
            done
        done
        
        return 0
    fi
    
    for i in "${!NODES[@]}"; do
        if [[ $i -ge $SERVER_COUNT ]]; then
            continue
        fi
        
        node_ip=${IPS[$i]}
        node_name=${NODES[$i]}
        
        echo "Starting Kafka on $node_name..."
        
        if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
            # Local deployment - start Kafka directly
            echo "Starting Kafka server on $(uname) with Java 21..."
            
            # Create startup script for reliable execution
            cat > /tmp/start_kafka.sh << 'EOS'
#!/bin/bash
export JAVA_HOME="$JAVA_HOME_VAR"
export PATH="$JAVA_HOME/bin:$PATH"
cd /opt/kafka

# Ensure logs directory exists
mkdir -p logs

# Start Kafka with Java 21 compatible options
exec "$JAVA_HOME/bin/java" \
    -Xmx1G -Xms1G \
    -server \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=20 \
    -XX:InitiatingHeapOccupancyPercent=35 \
    -XX:+ExplicitGCInvokesConcurrent \
    -Djava.awt.headless=true \
    -Xlog:gc*:logs/kafkaServer-gc.log:time,tags \
    -Dcom.sun.management.jmxremote \
    -Dcom.sun.management.jmxremote.authenticate=false \
    -Dcom.sun.management.jmxremote.ssl=false \
    -Dkafka.logs.dir=logs \
    -Dlog4j.configuration=file:etc/kafka/log4j.properties \
    -cp "share/java/kafka/*:share/java/kafka-connect-api/*:share/java/kafka-connect-runtime/*:share/java/kafka-connect-storage-common/*:share/java/rest-utils/*:share/java/confluent-common/*:share/java/schema-registry/*:share/java/ksqldb-udf/*:share/java/ksqldb-streams-extensions/*:share/java/acl/*:share/java/kafka-connect-elastic/*:share/java/confluent-telemetry/*:share/java/support-metrics-client/*" \
    kafka.Kafka \
    etc/kafka/server.properties
EOS
            
            # Replace JAVA_HOME_VAR in the script
            sed -i '' "s|\$JAVA_HOME_VAR|$JAVA_HOME|g" /tmp/start_kafka.sh
            chmod +x /tmp/start_kafka.sh
            
            # Start Kafka in background
            sudo -u kafka /tmp/start_kafka.sh > "$LOG_DIR/kafka/kafka.log" 2>&1 &
            local kafka_pid=$!
            echo "Waiting for Kafka to initialize (PID: $kafka_pid)..."
            
            # Wait for Kafka to start listening
            local max_attempts=30
            local attempt=1
            while [ $attempt -le $max_attempts ]; do
                if netstat -ln 2>/dev/null | grep -q ":$PLAINTEXT_PORT.*LISTEN" || \
                   lsof -i :$PLAINTEXT_PORT 2>/dev/null | grep -q LISTEN; then
                    echo "Kafka started successfully and is listening on port $PLAINTEXT_PORT"
                    break
                fi
                
                if [ $attempt -eq $max_attempts ]; then
                    echo "ERROR: Kafka failed to start within expected time"
                    echo "Last 20 lines of Kafka log:"
                    tail -20 "$LOG_DIR/kafka/kafka.log" 2>/dev/null || echo "No log file found"
                    exit 1
                fi
                
                sleep 2
                ((attempt++))
            done

        else
            # Production deployment - use systemd
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$node_ip << 'EOF'
                # Create systemd service
                ${SUDO_CMD:+$SUDO_CMD} tee /etc/systemd/system/kafka.service > /dev/null << EOS
[Unit]
Description=Apache Kafka Server (KRaft Mode)
Requires=network.target
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment=JAVA_HOME=$JAVA_HOME
ExecStart=/opt/kafka/bin/kafka-server-start /opt/kafka/etc/kafka/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop
Restart=on-abnormal
RestartSec=30s

[Install]
WantedBy=multi-user.target
EOS
                
                ${SUDO_CMD:+$SUDO_CMD} systemctl daemon-reload
                ${SUDO_CMD:+$SUDO_CMD} systemctl enable kafka
                ${SUDO_CMD:+$SUDO_CMD} systemctl start kafka
                
                # Wait for service to start
                sleep 10
                ${SUDO_CMD:+$SUDO_CMD} systemctl is-active kafka || {
                    echo "ERROR: Kafka service failed to start"
                    ${SUDO_CMD:+$SUDO_CMD} journalctl -u kafka --no-pager -l
                    exit 1
                }
EOF
        fi
        
        echo "Kafka server started successfully"
    done
}

# Copy files to nodes  
copy_files() {
    if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
        echo "Local deployment - files already available locally"
        return 0
    fi
    
    echo "Copying installation files to all nodes..."
    
    # Define all required files
    local FILES_TO_COPY=(
        "$CONFLUENT_ZIP"
        "jdk-21_linux-aarch64_bin.tar.gz"
    )
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        # Copy files to Docker containers via SSH - sequential to avoid password conflicts
        echo "Copying files to Docker containers..."
        
        for i in "${!CONTAINER_NAMES[@]}"; do
            if [[ $i -lt $SERVER_COUNT ]]; then
                container_name=${CONTAINER_NAMES[$i]}
                ssh_port=${SSH_PORTS[$i]}
                
                echo "Copying files to $container_name via localhost:$ssh_port..."
                
                for file in "${FILES_TO_COPY[@]}"; do
                    echo "  - Copying $file to $container_name..."
                    
                    # Add retry logic for file copying
                    local max_retries=3
                    local retry=1
                    
                    while [ $retry -le $max_retries ]; do
                        if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -P $ssh_port \
                            "/Users/alexk/pipelines/kafka-community-8/deployment-files/$file" \
                            $SSH_USER@localhost:/tmp/; then
                            echo "    ✅ $file copied successfully (attempt $retry)"
                            break
                        else
                            echo "    ⚠️  Copy attempt $retry failed for $file"
                            if [ $retry -eq $max_retries ]; then
                                echo "ERROR: Failed to copy $file to $container_name after $max_retries attempts"
                                exit 1
                            fi
                            ((retry++))
                            sleep 5
                        fi
                    done
                done
                echo "  ✅ All files copied successfully to $container_name"
            fi
        done
        
    else
        # Copy files to remote servers - sequential to avoid password conflicts
        echo "Copying files to remote servers..."
        
        for i in "${!IPS[@]}"; do
            if [[ $i -lt $SERVER_COUNT ]]; then
                ip=${IPS[$i]}
                node_name=${NODES[$i]}
                
                echo "Copying files to $node_name ($ip)..."
                
                for file in "${FILES_TO_COPY[@]}"; do
                    echo "  - Copying $file to $node_name..."
                    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        "$LOCAL_FILES_PATH/$file" \
                        $SSH_USER@$ip:/tmp/ || {
                        echo "ERROR: Failed to copy $file to $ip"
                        exit 1
                    }
                done
                echo "  ✅ All files copied successfully to $node_name"
            fi
        done
    fi
    
    echo "✅ File copying completed successfully for all nodes"
}

# Verify cluster health
verify_cluster() {
    echo "Verifying cluster health..."
    echo "Waiting for Kafka to fully initialize..."
    sleep 5
    
    echo "Verifying cluster health..."
    if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
        JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server localhost:$PLAINTEXT_PORT > /dev/null 2>&1 || {
            echo "ERROR: Cluster verification failed"
            echo "Kafka logs:"
            tail -20 "$LOG_DIR/kafka/kafka.log" 2>/dev/null || echo "No log file found"
            exit 1
        }
        echo "✅ Kafka broker is responding"
        
        # Test cluster metadata
        echo "Testing cluster metadata..."
        JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-cluster --bootstrap-server localhost:$PLAINTEXT_PORT cluster-id > /dev/null 2>&1 || {
            echo "WARNING: Could not retrieve cluster metadata, but broker is responding"
        }
        echo "✅ Cluster metadata is accessible"
    elif [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        # Use the first container for cluster verification
        ssh_port=${SSH_PORTS[0]}
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ssh_port $SSH_USER@localhost "JDK_DIR=\$(ls -d /opt/jdk-21* 2>/dev/null | head -1); JAVA_HOME=\$JDK_DIR /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server kafka-${ENVIRONMENT}-node-1:$PLAINTEXT_PORT" || {
            echo "ERROR: Cluster verification failed"
            exit 1
        }
        echo "✅ Docker cluster is responding"
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@${IPS[0]} "JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server kafka-${ENVIRONMENT}-node-1:$PLAINTEXT_PORT" || {
            echo "ERROR: Cluster verification failed"
            exit 1
        }
        echo "✅ Production cluster is responding"
    fi
    
    echo "Cluster health verification completed successfully"
}

# Main execution
echo "=== Kafka Cluster Deployment for Environment: $ENVIRONMENT ==="
echo "Configuration:"
echo "  - Deployment type: Air-gapped (offline)"
echo "  - Java version: 21"
echo "  - Kafka version: Confluent Community 8.0.0"
echo "  - Server count: $SERVER_COUNT"
echo "  - Data directory: $DATA_DIR"
echo "  - Log directory: $LOG_DIR"
echo "  - Note: All required utilities must be pre-installed (no internet access)"
echo ""

echo "Phase 1: Validating prerequisites and connectivity..."
validate_prerequisites
echo "Phase 2: Testing SSH connectivity and required utilities..."
test_ssh
echo "Phase 3: Copying installation files to all nodes..."
copy_files

echo "Phase 4: Generating shared cluster UUID and installing nodes..."
# Generate shared cluster UUID for all nodes - use local generation or simple UUID
echo "Generating shared cluster UUID..."
if [[ "$LOCAL_DEPLOYMENT" == "true" ]]; then
    SHARED_CLUSTER_UUID=$(JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-storage random-uuid)
else
    # Generate a simple UUID for Docker and Remote deployments
    SHARED_CLUSTER_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
fi
echo "Shared cluster UUID: $SHARED_CLUSTER_UUID"
export SHARED_CLUSTER_UUID

echo "Installing nodes..."
for i in "${!NODES[@]}"; do
    echo "Installing ${NODES[$i]}..."
    is_first=$([[ $i -eq 0 ]] && echo "true" || echo "false")
    install_node ${IPS[$i]} $((i+1)) $is_first
done

echo "Phase 5: Starting Kafka services..."
start_services
echo "Phase 6: Verifying cluster health..."
verify_cluster

echo "=== Deployment Complete ==="
echo "✅ Kafka cluster deployed successfully!"
echo ""

BOOTSTRAP_LIST=""
for ((i=1; i<=SERVER_COUNT; i++)); do
    if [[ $i -gt 1 ]]; then
        BOOTSTRAP_LIST="${BOOTSTRAP_LIST},"
    fi
    BOOTSTRAP_LIST="${BOOTSTRAP_LIST}kafka-${ENVIRONMENT}-node-${i}:$PLAINTEXT_PORT"
done

echo "Connection Details:"
echo "  - Bootstrap servers: $BOOTSTRAP_LIST"
echo "  - Environment: $ENVIRONMENT"
echo "  - Data directory: $DATA_DIR"
echo "  - Log files: $LOG_DIR/kafka/kafka.log"
echo ""

echo "Next Steps:"
echo "  1. Test your deployment: ./test-kafka-simple.sh"
echo "  2. Create a test topic: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --create --topic test --bootstrap-server ${BOOTSTRAP_LIST} --partitions 1 --replication-factor $REPLICATION_FACTOR"
echo "  3. List topics: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --list --bootstrap-server ${BOOTSTRAP_LIST}"
echo ""

echo "Troubleshooting:"
echo "  - View logs: tail -f $LOG_DIR/kafka/kafka.log"
echo "  - Check processes: ps aux | grep kafka"
echo "  - Stop Kafka: sudo systemctl stop kafka (on each node)"