#!/bin/bash

set -e

# Prompt for environment name
read -p "Enter environment name (alphanumeric only): " ENVIRONMENT
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "ERROR: Environment name must be alphanumeric only"
    exit 1
fi

# Configuration for 1-server local deployment
SERVER_COUNT=1
LOCAL_DEPLOYMENT=true

# Server configuration
declare -a HOSTNAMES=("localhost")
declare -a IPS=("127.0.0.1")
NODES=("localhost")

# Credentials
SSH_USER="$(whoami)"
SSH_KEY_PATH=""
KAFKA_USER="kafka"
KAFKA_GROUP="kafka"

# Network configuration
PLAINTEXT_PORT=9092
CONTROLLER_PORT=9093

# Storage configuration
DATA_DIR="/tmp/kafka"
LOG_DIR="/tmp/log/confluent"

# Installation files
LOCAL_FILES_PATH="/Users/alexk/pipelines/kafka-community-8/deployment-files"
CONFLUENT_ZIP="confluent-community-8.0.0.zip"
JDK_ARCHIVE="jdk-21.0.8-macos-x64.tar.gz"
JAVA_HOME="/opt/jdk-21.0.8.jdk/Contents/Home"

# Kafka configuration
PARTITIONS_PER_TOPIC=24
RETENTION_HOURS=24
SEGMENT_RETENTION_HOURS=1
REPLICATION_FACTOR=1
MIN_INSYNC_REPLICAS=1
AUTO_CREATE_TOPICS=false

export ENVIRONMENT
export SERVER_COUNT

# Pre-deployment validation
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check if running as root or with sudo access
    if [[ $EUID -eq 0 ]]; then
        echo "WARNING: Running as root. This is not recommended."
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        echo "ERROR: This script requires sudo access"
        exit 1
    fi
    
    # Validate Java installation
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
    
    if [[ ! -f "$JAVA_HOME/bin/java" ]]; then
        echo "ERROR: Java 21 not found at $JAVA_HOME"
        echo "Expected: $JAVA_HOME/bin/java"
        exit 1
    fi
    
    # Test Java version
    JAVA_VERSION=$("$JAVA_HOME/bin/java" -version 2>&1 | head -n1 | cut -d'"' -f2)
    echo "Found Java version: $JAVA_VERSION"
    
    # Validate Confluent distribution
    if [[ ! -f "$LOCAL_FILES_PATH/$CONFLUENT_ZIP" ]]; then
        echo "ERROR: $CONFLUENT_ZIP not found in $LOCAL_FILES_PATH"
        echo "Please ensure the Confluent Community distribution is downloaded"
        exit 1
    fi
    
    # Validate JDK archive
    if [[ ! -f "$LOCAL_FILES_PATH/$JDK_ARCHIVE" ]]; then
        echo "ERROR: $JDK_ARCHIVE not found in $LOCAL_FILES_PATH"
        echo "Please ensure the JDK archive is available"
        exit 1
    fi
    
    # Check available disk space (require at least 2GB)
    AVAILABLE_SPACE=$(df /tmp | tail -1 | awk '{print $4}')
    if [[ $AVAILABLE_SPACE -lt 2097152 ]]; then  # 2GB in KB
        echo "WARNING: Less than 2GB available space in /tmp"
    fi
    
    # Check if ports are available
    if lsof -i :$PLAINTEXT_PORT >/dev/null 2>&1; then
        echo "ERROR: Port $PLAINTEXT_PORT is already in use"
        exit 1
    fi
    
    if lsof -i :$CONTROLLER_PORT >/dev/null 2>&1; then
        echo "ERROR: Port $CONTROLLER_PORT is already in use"
        exit 1
    fi
    
    echo "Prerequisites validation completed successfully"
}

# Verify RHEL 8 (skip for local)
verify_os() {
    echo "Local deployment - skipping OS verification"
    return 0
}

# Test SSH connectivity (skip for local)
test_ssh() {
    echo "Local deployment - skipping SSH test"
    return 0
}

# Install on local node
install_node() {
    local node_ip=$1
    local node_id=$2
    local is_first_node=$3
    
    echo "Installing Kafka on node $node_id..."
    
    # Verify Java installation
    if [[ ! -f "$JAVA_HOME/bin/java" ]]; then
        echo "ERROR: Java not found at $JAVA_HOME"
        echo "Please ensure JDK archive is available and extracted"
        exit 1
    fi
    
    # Verify Confluent zip exists
    if [[ ! -f "$LOCAL_FILES_PATH/$CONFLUENT_ZIP" ]]; then
        echo "ERROR: $CONFLUENT_ZIP not found in $LOCAL_FILES_PATH"
        exit 1
    fi
    
    # Verify JDK archive exists
    if [[ ! -f "$LOCAL_FILES_PATH/$JDK_ARCHIVE" ]]; then
        echo "ERROR: $JDK_ARCHIVE not found in $LOCAL_FILES_PATH"
        exit 1
    fi
    
    # Create kafka group and user (macOS compatible)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS group and user creation
        if ! dscl . -read /Groups/$KAFKA_GROUP >/dev/null 2>&1; then
            sudo dscl . -create /Groups/$KAFKA_GROUP
            sudo dscl . -create /Groups/$KAFKA_GROUP PrimaryGroupID 502
        fi
        
        if ! dscl . -read /Users/$KAFKA_USER >/dev/null 2>&1; then
            sudo dscl . -create /Users/$KAFKA_USER
            sudo dscl . -create /Users/$KAFKA_USER UserShell /bin/false
            sudo dscl . -create /Users/$KAFKA_USER RealName "Kafka Service User"
            sudo dscl . -create /Users/$KAFKA_USER UniqueID 502
            sudo dscl . -create /Users/$KAFKA_USER PrimaryGroupID 502
            sudo dscl . -create /Users/$KAFKA_USER NFSHomeDirectory /opt/kafka
        fi
    else
        # Linux group and user creation
        if ! getent group $KAFKA_GROUP >/dev/null 2>&1; then
            sudo groupadd -r $KAFKA_GROUP
        fi
        
        if ! id $KAFKA_USER >/dev/null 2>&1; then
            sudo useradd -r -g $KAFKA_GROUP -s /bin/false -d /opt/kafka $KAFKA_USER
        fi
    fi
    
    # Create all required directories with proper structure
    echo "Creating directory structure..."
    sudo mkdir -p /opt/kafka
    sudo mkdir -p $DATA_DIR/logs
    sudo mkdir -p $LOG_DIR/kafka
    
    # Set initial permissions for directories
    sudo chown -R $KAFKA_USER:$KAFKA_GROUP $DATA_DIR $LOG_DIR
    
    # Clean up any existing Kafka installations
    echo "Cleaning up existing installations..."
    cd /opt
    sudo rm -rf kafka confluent-* jdk-* 2>/dev/null || true
    
    # Extract Confluent Community distribution
    echo "Extracting Confluent Community $CONFLUENT_ZIP..."
    sudo unzip -q "$LOCAL_FILES_PATH/$CONFLUENT_ZIP"
    
    # Handle different extraction patterns - the ZIP extracts to confluent-8.0.0/
    if [[ -d "confluent-community-8.0.0" ]]; then
        sudo mv confluent-community-8.0.0 kafka
    elif [[ -d "confluent-8.0.0" ]]; then
        # Move contents from extracted directory to kafka directory
        sudo mkdir -p kafka
        sudo mv confluent-8.0.0/* kafka/
        sudo rmdir confluent-8.0.0
    else
        echo "ERROR: Unexpected directory structure after extraction"
        echo "Available directories:"
        ls -la
        exit 1
    fi
    
    # Set proper ownership for Kafka installation
    sudo chown -R $KAFKA_USER:$KAFKA_GROUP /opt/kafka
    
    # Verify critical Kafka binaries exist
    if [[ ! -f "/opt/kafka/bin/kafka-storage" ]]; then
        echo "ERROR: kafka-storage binary not found"
        exit 1
    fi
    
    if [[ ! -f "/opt/kafka/bin/kafka-server-start" ]]; then
        echo "ERROR: kafka-server-start binary not found"
        exit 1
    fi
    
    # Generate cluster UUID for KRaft initialization
    echo "Generating cluster UUID..."
    CLUSTER_UUID=$(/opt/kafka/bin/kafka-storage random-uuid)
    echo "Cluster UUID: $CLUSTER_UUID"
    
    # Build quorum voters list (single node for local deployment)
    QUORUM_VOTERS="1@localhost:$CONTROLLER_PORT"
    echo "Quorum voters: $QUORUM_VOTERS"
    
    # Create server.properties configuration
    echo "Creating Kafka server configuration..."
    sudo tee /opt/kafka/etc/kafka/server.properties > /dev/null << EOC
process.roles=controller,broker
node.id=$node_id
controller.quorum.voters=$QUORUM_VOTERS
listeners=PLAINTEXT://:$PLAINTEXT_PORT,CONTROLLER://:$CONTROLLER_PORT
inter.broker.listener.name=PLAINTEXT
advertised.listeners=PLAINTEXT://localhost:$PLAINTEXT_PORT
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
log.retention.ms=$(($RETENTION_HOURS * 3600000))
log.segment.ms=$(($SEGMENT_RETENTION_HOURS * 3600000))
EOC
    
    # Verify configuration file was created
    if [[ ! -f "/opt/kafka/etc/kafka/server.properties" ]]; then
        echo "ERROR: Failed to create server.properties"
        exit 1
    fi
    
    echo "Server configuration created successfully"
    
    # Format storage for KRaft mode
    echo "Formatting Kafka storage for KRaft mode..."
    sudo -u $KAFKA_USER JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-storage format -t $CLUSTER_UUID -c /opt/kafka/etc/kafka/server.properties
    
    # Verify storage formatting completed
    if [[ ! -f "$DATA_DIR/logs/meta.properties" ]]; then
        echo "ERROR: Storage formatting failed - meta.properties not created"
        exit 1
    fi
    
    echo "Storage formatting completed successfully"
    
    # Start Kafka (platform-specific)
    echo "Starting Kafka server..."
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS - start Kafka using a simple background process with logging
        echo "Starting Kafka server on macOS with Java 21..."
        
        # Create a startup script that can run independently
        cat > /tmp/start_kafka.sh << 'KAFKASTART'
#!/bin/bash
export JAVA_HOME=/Users/alexk/pipelines/kafka-community-8/deployment-files/jdk-21.0.8.jdk/Contents/Home
cd /opt/kafka
mkdir -p logs
exec $JAVA_HOME/bin/java -Xmx1G -Xms1G -server -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+ExplicitGCInvokesConcurrent -Djava.awt.headless=true -Xlog:gc*:logs/kafkaServer-gc.log:time,tags -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Dkafka.logs.dir=logs -Dlog4j.configuration=file:etc/kafka/log4j.properties -cp /opt/kafka/share/java/kafka/*:/opt/kafka/share/java/kafka-connect-api/*:/opt/kafka/share/java/kafka-connect-runtime/*:/opt/kafka/share/java/kafka-connect-storage-common/*:/opt/kafka/share/java/rest-utils/*:/opt/kafka/share/java/confluent-common/*:/opt/kafka/share/java/schema-registry/*:/opt/kafka/share/java/ksqldb-udf/*:/opt/kafka/share/java/ksqldb-streams-extensions/*:/opt/kafka/share/java/acl/*:/opt/kafka/share/java/kafka-connect-elastic/*:/opt/kafka/share/java/confluent-telemetry/*:/opt/kafka/share/java/support-metrics-client/* kafka.Kafka etc/kafka/server.properties
KAFKASTART
        
        chmod +x /tmp/start_kafka.sh
        sudo chown kafka:kafka /tmp/start_kafka.sh
        
        # Start Kafka in background
        sudo -u $KAFKA_USER /tmp/start_kafka.sh > /tmp/log/confluent/kafka/kafka.log 2>&1 &
        KAFKA_PID=$!
        
        # Wait for startup
        echo "Waiting for Kafka to initialize (PID: $KAFKA_PID)..."
        sleep 20
        
        # Check if Kafka is running by testing the ports
        if ! lsof -i :$PLAINTEXT_PORT >/dev/null 2>&1; then
            echo "ERROR: Kafka broker port $PLAINTEXT_PORT is not active"
            echo "Checking process status..."
            if ps -p $KAFKA_PID >/dev/null 2>&1; then
                echo "Process $KAFKA_PID is still running, may need more time to initialize"
            else
                echo "Process $KAFKA_PID has died"
            fi
            echo "Recent logs:"
            tail -20 /tmp/log/confluent/kafka/kafka.log 2>/dev/null || echo "No logs available"
            exit 1
        else
            echo "Kafka started successfully and is listening on port $PLAINTEXT_PORT"
        fi
    else
        # Linux - create systemd service
        sudo tee /etc/systemd/system/kafka.service > /dev/null << EOS
[Unit]
Description=Apache Kafka Server (KRaft Mode)
Requires=network.target
After=network.target

[Service]
Type=simple
User=$KAFKA_USER
Group=$KAFKA_GROUP
Environment=JAVA_HOME=$JAVA_HOME
ExecStart=/opt/kafka/bin/kafka-server-start /opt/kafka/etc/kafka/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop
Restart=on-abnormal
RestartSec=30s

[Install]
WantedBy=multi-user.target
EOS
        
        sudo systemctl daemon-reload
        sudo systemctl enable kafka
        sudo systemctl start kafka
        
        # Verify service started successfully
        if ! sudo systemctl is-active --quiet kafka; then
            echo "ERROR: Kafka service failed to start"
            echo "Check logs: sudo journalctl -u kafka -f"
            exit 1
        fi
    fi
    
    echo "Kafka server started successfully"
}

# Copy files to nodes (skip for local)
copy_files() {
    echo "Local deployment - files already available locally"
    return 0
}

# Verify cluster health
verify_cluster() {
    echo "Waiting for Kafka to fully initialize..."
    sleep 15
    
    echo "Verifying cluster health..."
    
    # Test Kafka connectivity with retries
    MAX_RETRIES=5
    RETRY_COUNT=0
    
    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        if JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server localhost:$PLAINTEXT_PORT > /dev/null 2>&1; then
            echo "✅ Kafka broker is responding"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Kafka not responding yet, waiting..."
            sleep 5
        fi
    done
    
    if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
        echo "❌ Kafka broker is not responding after $MAX_RETRIES attempts"
        echo "Check logs: sudo tail -f $LOG_DIR/kafka/kafka.log"
        echo "Check processes: ps aux | grep kafka"
        exit 1
    fi
    
    # Test cluster metadata
    echo "Testing cluster metadata..."
    if JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-log-dirs --bootstrap-server localhost:$PLAINTEXT_PORT --describe >/dev/null 2>&1; then
        echo "✅ Cluster metadata is accessible"
    else
        echo "❌ Cluster metadata test failed"
        exit 1
    fi
    
    echo "Cluster health verification completed successfully"
}

# Main execution
echo "=== Kafka Cluster Deployment for Environment: $ENVIRONMENT ==="
echo "Configuration:"
echo "  - Deployment type: Local (single-node)"
echo "  - Java version: $(basename $JAVA_HOME)"
echo "  - Kafka version: Confluent Community 8.0.0"
echo "  - Data directory: $DATA_DIR"
echo "  - Log directory: $LOG_DIR"
echo ""

echo "Validating prerequisites..."
validate_prerequisites

echo "Testing SSH connectivity..."
test_ssh

echo "Copying installation files..."
copy_files

echo "Installing nodes..."
for i in "${!NODES[@]}"; do
    echo "Installing ${NODES[$i]}..."
    is_first=$([[ $i -eq 0 ]] && echo "true" || echo "false")
    install_node ${IPS[$i]} $((i+1)) $is_first
done

echo "Verifying cluster health..."
verify_cluster

echo "=== Deployment Complete ==="
echo "✅ Kafka cluster deployed successfully!"
echo ""
echo "Connection Details:"
echo "  - Bootstrap servers: localhost:$PLAINTEXT_PORT"
echo "  - Environment: $ENVIRONMENT"
echo "  - Data directory: $DATA_DIR"
echo "  - Log files: $LOG_DIR/kafka/kafka.log"
echo ""
echo "Next Steps:"
echo "  1. Test your deployment: ./test-kafka-simple.sh"
echo "  2. Create a test topic: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --create --topic test --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1"
echo "  3. List topics: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --list --bootstrap-server localhost:9092"
echo ""
echo "Troubleshooting:"
echo "  - View logs: tail -f $LOG_DIR/kafka/kafka.log"
echo "  - Check processes: ps aux | grep kafka"
echo "  - Stop Kafka: sudo pkill -f kafka-server-start"
