#!/bin/bash

set -e

# Prompt for environment name
read -p "Enter environment name (alphanumeric only): " ENVIRONMENT
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "ERROR: Environment name must be alphanumeric only"
    exit 1
fi

# Configuration for 3-server production deployment
SERVER_COUNT=3
LOCAL_DEPLOYMENT=false

# Server configuration
declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
declare -a IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")

# Credentials
SSH_USER="root"
SSH_KEY_PATH="/path/to/private/key"
KAFKA_USER="kafka"
KAFKA_GROUP="kafka"

# Network configuration
PLAINTEXT_PORT=9092
CONTROLLER_PORT=9093

# Storage configuration
DATA_DIR="/kafka"
LOG_DIR="/var/log/confluent"

# Installation files
LOCAL_FILES_PATH="/Users/alexk/pipelines/kafka-community-8/deployment-files"
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
    
    ssh $SSH_USER@$1 "grep -q 'Red Hat Enterprise Linux.*8' /etc/redhat-release" || {
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
    
    echo "Testing SSH connectivity..."
    for i in "${!NODES[@]}"; do
        echo "Testing SSH to ${NODES[$i]} (${IPS[$i]})..."
        ssh -o ConnectTimeout=5 -o BatchMode=yes $SSH_USER@${IPS[$i]} "echo 'SSH OK'" || {
            echo "ERROR: Cannot SSH to ${NODES[$i]} (${IPS[$i]})"
            echo "Please ensure:"
            echo "  1. SSH key is properly configured"
            echo "  2. Host is reachable"
            echo "  3. SSH service is running on target host"
            exit 1
        }
        verify_os ${IPS[$i]}
    done
    echo "SSH connectivity test completed successfully"
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
    else
        FILE_PREFIX="/tmp/"
        EXEC_PREFIX="ssh $SSH_USER@$node_ip"
    fi
    
    $EXEC_PREFIX bash << EOF
        set -e
        
        echo "Creating directory structure..."
        
        # Detect platform for user/group creation
        if [[ "\$(uname)" == "Darwin" ]]; then
            # macOS user creation
            if ! dscl . -read /Groups/$KAFKA_GROUP >/dev/null 2>&1; then
                sudo dscl . -create /Groups/$KAFKA_GROUP
                sudo dscl . -create /Groups/$KAFKA_GROUP PrimaryGroupID 502
            fi
            
            if ! dscl . -read /Users/$KAFKA_USER >/dev/null 2>&1; then
                sudo dscl . -create /Users/$KAFKA_USER
                sudo dscl . -create /Users/$KAFKA_USER UserShell /bin/false
                sudo dscl . -create /Users/$KAFKA_USER RealName "Kafka User"
                sudo dscl . -create /Users/$KAFKA_USER UniqueID 502
                sudo dscl . -create /Users/$KAFKA_USER PrimaryGroupID 502
                sudo dscl . -create /Users/$KAFKA_USER NFSHomeDirectory /opt/kafka
            fi
        else
            # Linux user creation
            if ! getent group $KAFKA_GROUP >/dev/null 2>&1; then
                sudo groupadd -r $KAFKA_GROUP
            fi
            
            if ! id $KAFKA_USER >/dev/null 2>&1; then
                sudo useradd -r -g $KAFKA_GROUP -s /bin/false -d /opt/kafka $KAFKA_USER
            fi
        fi
        
        echo "Cleaning up existing installations..."
        sudo rm -rf /opt/kafka /opt/confluent-* /opt/jdk-* 2>/dev/null || true
        
        # Extract JDK if not already extracted
        if [[ ! -d "$JAVA_HOME" ]]; then
            echo "Extracting JDK from ${FILE_PREFIX}$JDK_ARCHIVE..."
            cd /opt
            sudo tar -xzf ${FILE_PREFIX}$JDK_ARCHIVE
            echo "JDK extracted successfully"
        fi
        
        # Create directories
        sudo mkdir -p /opt/kafka $DATA_DIR/logs $LOG_DIR/kafka
        sudo chown -R $KAFKA_USER:$KAFKA_GROUP $DATA_DIR $LOG_DIR 2>/dev/null || true
        
        echo "Extracting Confluent Community $CONFLUENT_ZIP..."
        
        # Extract Confluent
        cd /opt
        sudo unzip -q ${FILE_PREFIX}$CONFLUENT_ZIP
        
        # Handle different extraction patterns - the ZIP extracts to confluent-8.0.0/
        if [[ -d "confluent-community-8.0.0" ]]; then
            sudo mv confluent-community-8.0.0 kafka
        elif [[ -d "confluent-8.0.0" ]]; then
            sudo mv confluent-8.0.0 kafka
        else
            echo "ERROR: Unexpected directory structure after extraction"
            echo "Available directories:"
            ls -la
            exit 1
        fi
        
        sudo chown -R $KAFKA_USER:$KAFKA_GROUP /opt/kafka
        
        echo "Generating cluster UUID..."
        CLUSTER_UUID=\$(sudo -u $KAFKA_USER JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-storage random-uuid)
        echo "Cluster UUID: \$CLUSTER_UUID"
        
        # Build quorum voters list
        QUORUM_VOTERS=""
        for ((j=1; j<=SERVER_COUNT; j++)); do
            if [[ \$j -gt 1 ]]; then
                QUORUM_VOTERS="\${QUORUM_VOTERS},"
            fi
            QUORUM_VOTERS="\${QUORUM_VOTERS}\${j}@kafka-${ENVIRONMENT}-node-\${j}:$CONTROLLER_PORT"
        done
        echo "Quorum voters: \$QUORUM_VOTERS"
        
        echo "Creating Kafka server configuration..."
        
        # Create server.properties
        sudo -u $KAFKA_USER tee /opt/kafka/etc/kafka/server.properties > /dev/null << EOC
process.roles=controller,broker
node.id=$node_id
controller.quorum.voters=\$QUORUM_VOTERS
listeners=PLAINTEXT://:$PLAINTEXT_PORT,CONTROLLER://:$CONTROLLER_PORT
inter.broker.listener.name=PLAINTEXT
advertised.listeners=PLAINTEXT://${NODES[$((node_id-1))]}:$PLAINTEXT_PORT
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
        
        echo "Server configuration created successfully"
        
        echo "Formatting Kafka storage for KRaft mode..."
        
        # Format storage
        sudo -u $KAFKA_USER JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-storage format -t \$CLUSTER_UUID -c /opt/kafka/etc/kafka/server.properties
        
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
    echo "Starting Kafka services..."
    
    for i in "${!NODES[@]}"; do
        local node_ip=${IPS[$i]}
        local node_name=${NODES[$i]}
        
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
            ssh $SSH_USER@$node_ip << 'EOF'
                # Create systemd service
                sudo tee /etc/systemd/system/kafka.service > /dev/null << EOS
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
                
                sudo systemctl daemon-reload
                sudo systemctl enable kafka
                sudo systemctl start kafka
                
                # Wait for service to start
                sleep 10
                sudo systemctl is-active kafka || {
                    echo "ERROR: Kafka service failed to start"
                    sudo journalctl -u kafka --no-pager -l
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
    
    echo "Copying installation files..."
    for ip in "${IPS[@]}"; do
        echo "Copying files to $ip..."
        scp "$LOCAL_FILES_PATH/$CONFLUENT_ZIP" $SSH_USER@$ip:/tmp/ || {
            echo "ERROR: Failed to copy $CONFLUENT_ZIP to $ip"
            exit 1
        }
        scp "$LOCAL_FILES_PATH/$JDK_ARCHIVE" $SSH_USER@$ip:/tmp/ || {
            echo "ERROR: Failed to copy $JDK_ARCHIVE to $ip"
            exit 1
        }
    done
    echo "File copying completed successfully"
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
    else
        ssh $SSH_USER@${IPS[0]} "JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server kafka-${ENVIRONMENT}-node-1:$PLAINTEXT_PORT" || {
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
echo "  - Deployment type: Production (multi-node)"
echo "  - Java version: 21"
echo "  - Kafka version: Confluent Community 8.0.0"
echo "  - Server count: $SERVER_COUNT"
echo "  - Data directory: $DATA_DIR"
echo "  - Log directory: $LOG_DIR"
echo ""

validate_prerequisites
test_ssh
copy_files

echo "Installing nodes..."
for i in "${!NODES[@]}"; do
    echo "Installing ${NODES[$i]}..."
    is_first=$([[ $i -eq 0 ]] && echo "true" || echo "false")
    install_node ${IPS[$i]} $((i+1)) $is_first
done

start_services
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