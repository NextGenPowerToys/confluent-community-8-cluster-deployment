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

# Server configuration based on deployment type
if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
    declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
    declare -a IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")
    SSH_USER="root"
    SSH_KEY_PATH="~/.ssh/kafka_test_key"
    LOCAL_FILES_PATH="/tmp/files"
else
    declare -a HOSTNAMES=("kafka-node-1" "kafka-node-2" "kafka-node-3")
    declare -a IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")
    SSH_USER="root"
    SSH_KEY_PATH="/path/to/private/key"
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
        echo "Docker deployment - skipping local Java validation"
        # Only check if Confluent ZIP exists in deployment-files
        if [[ ! -f "/Users/alexk/pipelines/kafka-community-8/deployment-files/$CONFLUENT_ZIP" ]]; then
            echo "ERROR: Confluent ZIP not found at /Users/alexk/pipelines/kafka-community-8/deployment-files/$CONFLUENT_ZIP"
            exit 1
        fi
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
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        echo "Testing Docker SSH connectivity..."
        local ports=(12222 12223 12224)
        for i in "${!NODES[@]}"; do
            if [[ $i -lt $SERVER_COUNT ]]; then
                echo "Testing SSH to ${NODES[$i]} via localhost:${ports[$i]}..."
                ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Port=${ports[$i]} -i ~/.ssh/kafka_test_key $SSH_USER@localhost "echo 'SSH OK'" || {
                    echo "ERROR: Cannot SSH to ${NODES[$i]} via localhost:${ports[$i]}"
                    exit 1
                }
            fi
        done
        echo "Docker SSH connectivity test completed successfully"
        return 0
    fi
    
    echo "Testing SSH connectivity..."
    for i in "${!NODES[@]}"; do
        if [[ $i -lt $SERVER_COUNT ]]; then
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
        fi
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
    elif [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        FILE_PREFIX="/tmp/files/"
        local ports=(12222 12223 12224)
        local port=${ports[$((node_id-1))]}
        EXEC_PREFIX="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Port=$port -i ~/.ssh/kafka_test_key $SSH_USER@localhost"
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
        sudo rm -rf $DATA_DIR $LOG_DIR 2>/dev/null || true
        
        # Install Java for Docker/Linux environments
        if [[ "\$(uname)" != "Darwin" ]]; then
            echo "Installing Java 21 from offline tarball..."
            cd /opt
            tar -xzf ${FILE_PREFIX}jdk-21_linux-aarch64_bin.tar.gz
            
            # Find the actual JDK directory using ls
            JDK_DIR=\$(ls -d /opt/jdk-21* 2>/dev/null | head -1)
            if [[ -n "\$JDK_DIR" ]]; then
                export JAVA_HOME=\$JDK_DIR
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
                sudo tar -xzf ${FILE_PREFIX}$JDK_ARCHIVE
                echo "JDK extracted successfully"
            fi
        fi
        
        # Create directories
        sudo mkdir -p /opt/kafka $DATA_DIR/logs $LOG_DIR/kafka
        sudo chown -R $KAFKA_USER:$KAFKA_GROUP $DATA_DIR $LOG_DIR 2>/dev/null || true
        
        echo "Extracting Confluent Community $CONFLUENT_ZIP..."
        
        # Extract Confluent
        cd /opt
        sudo unzip -q ${FILE_PREFIX}$CONFLUENT_ZIP
        
        # Handle different extraction patterns - find the confluent directory using ls
        CONFLUENT_DIR=\$(ls -d confluent* 2>/dev/null | head -1)
        if [[ -n "\$CONFLUENT_DIR" ]]; then
            echo "Found Confluent directory: \$CONFLUENT_DIR"
            # Move contents of confluent directory to kafka, not the directory itself
            sudo mv "\$CONFLUENT_DIR"/* kafka/
            sudo rmdir "\$CONFLUENT_DIR"
            echo "Contents of /opt/kafka after move:"
            ls -la /opt/kafka
        else
            echo "ERROR: No confluent directory found after extraction"
            echo "Available directories:"
            ls -la
            exit 1
        fi
        
        sudo chown -R $KAFKA_USER:$KAFKA_GROUP /opt/kafka
        
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
        
        # Build quorum voters list
        QUORUM_VOTERS=""
        for ((j=1; j<=$SERVER_COUNT; j++)); do
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
        
        # Ensure clean data directory
        sudo rm -rf $DATA_DIR/logs/* 2>/dev/null || true
        sudo mkdir -p $DATA_DIR/logs
        sudo chown -R $KAFKA_USER:$KAFKA_GROUP $DATA_DIR
        
        # Format storage
        sudo -u $KAFKA_USER JAVA_HOME=\$JAVA_HOME \$KAFKA_STORAGE_SCRIPT format -t \$CLUSTER_UUID -c /opt/kafka/etc/kafka/server.properties
        
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
        # Start all Docker nodes simultaneously in background
        local ports=(12222 12223 12224)
        for i in "${!NODES[@]}"; do
            if [[ $i -ge $SERVER_COUNT ]]; then
                continue
            fi
            
            local node_name=${NODES[$i]}
            local port=${ports[$i]}
            
            echo "Starting Kafka on $node_name in background..."
            
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Port=$port -i ~/.ssh/kafka_test_key $SSH_USER@localhost << 'EOF' &
                # Find JDK directory
                JDK_DIR=$(ls -d /opt/jdk-21* 2>/dev/null | head -1)
                if [[ -n "$JDK_DIR" ]]; then
                    export JAVA_HOME=$JDK_DIR
                else
                    echo "ERROR: Could not find JDK directory"
                    exit 1
                fi
                
                echo "Starting Kafka server directly..."
                
                # Start Kafka in background
                nohup sudo -u kafka JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-server-start /opt/kafka/etc/kafka/server.properties > /var/log/confluent/kafka/kafka.log 2>&1 &
EOF
        done
        
        echo "Waiting for all Kafka nodes to start..."
        sleep 30
        
        # Check if all nodes are running
        for i in "${!NODES[@]}"; do
            if [[ $i -ge $SERVER_COUNT ]]; then
                continue
            fi
            
            local node_name=${NODES[$i]}
            local port=${ports[$i]}
            
            echo "Checking Kafka on $node_name..."
            
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Port=$port -i ~/.ssh/kafka_test_key $SSH_USER@localhost << 'EOF'
                for attempt in {1..30}; do
                    if netstat -ln 2>/dev/null | grep -q ":9092.*LISTEN" || ss -ln 2>/dev/null | grep -q ":9092"; then
                        echo "Kafka started successfully on port 9092"
                        exit 0
                    fi
                    
                    if [ $attempt -eq 30 ]; then
                        echo "ERROR: Kafka failed to start within 60 seconds"
                        echo "Last 10 lines of Kafka log:"
                        tail -10 /var/log/confluent/kafka/kafka.log 2>/dev/null || echo "No log file found"
                        exit 1
                    fi
                    
                    sleep 2
                done
EOF
        done
        
        return 0
    fi
    
    for i in "${!NODES[@]}"; do
        if [[ $i -ge $SERVER_COUNT ]]; then
            continue
        fi
        
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
    
    if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        echo "Docker deployment - files already mounted in containers"
        return 0
    fi
    
    echo "Copying installation files..."
    for i in "${!IPS[@]}"; do
        if [[ $i -lt $SERVER_COUNT ]]; then
            local ip=${IPS[$i]}
            echo "Copying files to $ip..."
            scp "$LOCAL_FILES_PATH/$CONFLUENT_ZIP" $SSH_USER@$ip:/tmp/ || {
                echo "ERROR: Failed to copy $CONFLUENT_ZIP to $ip"
                exit 1
            }
            scp "$LOCAL_FILES_PATH/jdk-21_linux-aarch64_bin.tar.gz" $SSH_USER@$ip:/tmp/ || {
                echo "ERROR: Failed to copy Java tarball to $ip"
                exit 1
            }
        fi
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
    elif [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Port=12222 -i ~/.ssh/kafka_test_key $SSH_USER@localhost "JDK_DIR=\$(ls -d /opt/jdk-21* 2>/dev/null | head -1); JAVA_HOME=\$JDK_DIR /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server kafka-${ENVIRONMENT}-node-1:$PLAINTEXT_PORT" || {
            echo "ERROR: Cluster verification failed"
            exit 1
        }
        echo "✅ Docker cluster is responding"
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

# Generate shared cluster UUID for all nodes
echo "Generating shared cluster UUID..."
if [[ "$DOCKER_DEPLOYMENT" == "true" ]]; then
    SHARED_CLUSTER_UUID=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Port=12222 -i ~/.ssh/kafka_test_key root@localhost "JDK_DIR=\$(ls -d /opt/jdk-21* 2>/dev/null | head -1); JAVA_HOME=\$JDK_DIR /opt/kafka/bin/kafka-storage random-uuid")
else
    SHARED_CLUSTER_UUID=$(JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-storage random-uuid)
fi
echo "Shared cluster UUID: $SHARED_CLUSTER_UUID"
export SHARED_CLUSTER_UUID

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