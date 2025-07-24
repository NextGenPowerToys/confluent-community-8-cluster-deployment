#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINERS=("kafka-test-node1" "kafka-test-node2" "kafka-test-node3" "kafka-ui")
SSH_PORTS=(2221 2222 2223)
ADMIN_USER="admin"
ADMIN_PASSWORD="password123"
ROOT_PASSWORD="rootpassword"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 {start|stop|restart|recreate|status|ssh-setup|test-ssh|logs|cleanup}"
    echo ""
    echo "Commands:"
    echo "  start     - Start all containers and configure SSH"
    echo "  stop      - Stop all containers"
    echo "  restart   - Restart all containers"
    echo "  recreate  - Stop, remove, and recreate all containers with SSH"
    echo "  status    - Show container status and SSH commands"
    echo "  ssh-setup - Configure and start SSH on all containers"
    echo "  test-ssh  - Test SSH connectivity to all containers"
    echo "  logs      - Show logs for all containers"
    echo "  cleanup   - Stop and remove containers and networks"
    echo ""
    exit 1
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=false
    
    # Check for docker and docker-compose
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed or not in PATH"
        missing_deps=true
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_error "docker-compose is not installed or not in PATH"
        missing_deps=true
    fi
    
    # Check for sshpass (needed for automated SSH testing)
    if ! command -v sshpass >/dev/null 2>&1; then
        print_warning "sshpass is not installed - SSH testing may require manual password entry"
        print_warning "Install with: brew install sshpass (macOS) or apt-get install sshpass (Linux)"
    fi
    
    if [ "$missing_deps" = true ]; then
        print_error "Missing required dependencies. Please install them before continuing."
        exit 1
    fi
}

# Function to clean SSH known_hosts entries for container ports
clean_ssh_known_hosts() {
    print_status "Cleaning SSH known_hosts entries for container ports..."
    
    for port in "${SSH_PORTS[@]}"; do
        ssh-keygen -R "[localhost]:$port" 2>/dev/null || true
    done
    
    print_status "SSH known_hosts entries cleaned"
}

# Function to pre-accept SSH host keys for containers
accept_ssh_host_keys() {
    print_status "Pre-accepting SSH host keys for containers..."
    
    # Wait a moment for SSH services to be fully ready
    sleep 2
    
    for i in "${!CONTAINERS[@]}"; do
        local container="${CONTAINERS[$i]}"
        local port="${SSH_PORTS[$i]}"
        
        # Use ssh-keyscan to add the host key automatically
        if command -v ssh-keyscan >/dev/null 2>&1; then
            ssh-keyscan -p "$port" localhost 2>/dev/null >> ~/.ssh/known_hosts || true
        fi
    done
    
    print_status "SSH host keys pre-accepted"
}

# Function to check if container is running
is_container_running() {
    local container=$1
    docker ps --filter "name=$container" --filter "status=running" --format "{{.Names}}" | grep -q "^$container$"
}

# Function to wait for container to be ready
wait_for_container() {
    local container=$1
    local max_attempts=60  # Increased from 30 to 60
    local attempt=1
    
    print_status "Waiting for container $container to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container" echo "Container ready" >/dev/null 2>&1; then
            # Additional check - ensure SSH packages are installed
            if docker exec "$container" bash -c "command -v sshd >/dev/null 2>&1" >/dev/null 2>&1; then
                print_status "Container $container is ready with SSH available"
                return 0
            else
                print_status "Container $container is running but SSH not yet available (attempt $attempt/$max_attempts)"
            fi
        fi
        
        echo -n "."
        sleep 3  # Increased from 2 to 3 seconds
        ((attempt++))
    done
    
    print_error "Container $container failed to become ready after $((max_attempts * 3)) seconds"
    return 1
}

# Function to configure SSH on a container using docker exec
configure_ssh() {
    local container=$1
    local max_retries=3
    local retry=1
    
    print_status "Configuring SSH on $container..."
    
    while [ $retry -le $max_retries ]; do
        if [ $retry -gt 1 ]; then
            print_status "Retry $retry/$max_retries for SSH configuration on $container..."
            sleep 5
        fi
        
        # Create a comprehensive SSH configuration script
        local ssh_config_script="
            # Wait a bit more for package installation to complete
            sleep 2
            
            # Install additional utilities if missing
            if ! command -v hostname >/dev/null 2>&1 || ! command -v ps >/dev/null 2>&1; then
                echo 'Installing additional packages...'
                dnf install -y hostname util-linux procps-ng iproute >/dev/null 2>&1 || true
            fi
            
            # Ensure SSH host keys exist
            if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
                echo 'Generating SSH host keys...'
                ssh-keygen -A >/dev/null 2>&1
            fi
            
            # Ensure users exist with correct passwords
            if ! id admin >/dev/null 2>&1; then
                useradd -m -s /bin/bash admin
                echo 'admin:$ADMIN_PASSWORD' | chpasswd
                usermod -aG wheel admin
            else
                # User exists, just update password
                echo 'admin:$ADMIN_PASSWORD' | chpasswd
            fi
            
            # Always update root password
            echo 'root:$ROOT_PASSWORD' | chpasswd
            
            # Configure SSH daemon
            sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
            sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
            sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
            grep -q 'PubkeyAuthentication yes' /etc/ssh/sshd_config || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
            
            # Stop any existing SSH daemon and start fresh
            pkill -f sshd || true
            sleep 2
            /usr/sbin/sshd
            
            # Verify SSH is running
            if pgrep sshd >/dev/null; then
                echo 'SSH configuration completed successfully'
                exit 0
            else
                echo 'SSH daemon failed to start'
                exit 1
            fi
        "
        
        # Execute with proper variable substitution
        if docker exec -e ADMIN_PASSWORD="$ADMIN_PASSWORD" -e ROOT_PASSWORD="$ROOT_PASSWORD" "$container" bash -c "$ssh_config_script" 2>/dev/null; then
            print_status "SSH configured successfully on $container"
            return 0
        else
            print_warning "SSH configuration attempt $retry failed on $container"
            ((retry++))
        fi
    done
    
    # Final fallback attempt with simpler approach
    print_warning "Trying simplified SSH configuration on $container..."
    if docker exec -e ADMIN_PASSWORD="$ADMIN_PASSWORD" -e ROOT_PASSWORD="$ROOT_PASSWORD" "$container" bash -c "
        echo \"admin:\$ADMIN_PASSWORD\" | chpasswd 2>/dev/null || true
        echo \"root:\$ROOT_PASSWORD\" | chpasswd 2>/dev/null || true
        pkill sshd 2>/dev/null || true
        sleep 1
        /usr/sbin/sshd 2>/dev/null && echo 'Simplified SSH setup completed'
    " 2>/dev/null; then
        print_status "Simplified SSH configuration succeeded on $container"
        return 0
    fi
    
    print_error "All SSH configuration attempts failed on $container"
    return 1
}

# Function to test SSH connectivity
test_ssh_connection() {
    local container=$1
    local port=$2
    
    # Test connection using nc (netcat) which is more reliable on macOS
    if command -v nc >/dev/null 2>&1; then
        # Use netcat to test port connectivity (without timeout on macOS as it can be problematic)
        if nc -z localhost "$port" 2>/dev/null; then
            print_status "SSH port $port for $container is accessible"
            
            # Test actual SSH connectivity by attempting a connection that should fail with auth error
            if command -v sshpass >/dev/null 2>&1; then
                # Use sshpass if available for automated testing
                if sshpass -p password123 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 admin@localhost -p "$port" 'echo SSH_TEST_SUCCESS' 2>/dev/null | grep -q "SSH_TEST_SUCCESS"; then
                    print_status "SSH service is responding on port $port (password authentication successful)"
                else
                    # Even if password auth fails, if we get a connection, SSH is working
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o PubkeyAuthentication=no admin@localhost -p "$port" true 2>&1 | grep -q "Permission denied"; then
                        print_status "SSH service is responding on port $port (connection established, authentication required)"
                    else
                        print_warning "SSH port $port is open but service may not be fully ready"
                    fi
                fi
            else
                # Fallback method without sshpass
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o PubkeyAuthentication=no admin@localhost -p "$port" true 2>&1 | grep -q "Permission denied"; then
                    print_status "SSH service is responding on port $port (connection established, authentication required)"
                else
                    print_warning "SSH port $port is open but service may not be fully ready"
                fi
            fi
            return 0
        else
            print_error "SSH port $port for $container is not accessible"
            return 1
        fi
    else
        # Fallback method using telnet if nc is not available
        if echo "quit" | telnet localhost "$port" 2>/dev/null | grep -q "SSH"; then
            print_status "SSH port $port for $container is accessible"
            return 0
        else
            print_error "SSH port $port for $container is not accessible"
            return 1
        fi
    fi
}

# Function to start containers
start_containers() {
    print_header "Starting Docker Containers"
    
    # Check dependencies before starting
    check_dependencies
    
    # Clean SSH known_hosts to avoid conflicts with recreated containers
    clean_ssh_known_hosts
    
    docker-compose up -d
    
    print_status "Waiting for containers to initialize..."
    sleep 15  # Increased from 10 to 15 seconds
    
    # Check if all containers are running
    local all_running=true
    for container in "${CONTAINERS[@]}"; do
        if is_container_running "$container"; then
            print_status "Container $container is running"
        else
            print_error "Container $container is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        print_error "Some containers failed to start"
        return 1
    fi
    
    # Wait for containers to be ready and configure SSH
    local ssh_success=true
    for container in "${CONTAINERS[@]}"; do
        if wait_for_container "$container"; then
            if configure_ssh "$container"; then
                print_status "SSH configured successfully on $container"
            else
                print_error "Failed to configure SSH on $container"
                ssh_success=false
            fi
        else
            print_error "Container $container failed to become ready"
            ssh_success=false
        fi
    done
    
    if [ "$ssh_success" = true ]; then
        print_status "All containers started and SSH configured successfully"
        
        # Pre-accept SSH host keys to avoid manual prompts
        accept_ssh_host_keys
    else
        print_warning "Some containers may have SSH configuration issues"
    fi
}

# Function to show container status
show_status() {
    print_header "Container Status"
    docker-compose ps
    
    echo ""
    print_header "SSH Connection Commands"
    
    for i in "${!CONTAINERS[@]}"; do
        local container="${CONTAINERS[$i]}"
        
        # Skip SSH info for kafka-ui since it doesn't have SSH
        if [[ "$container" == "kafka-ui" ]]; then
            echo -e "${BLUE}$container${NC} (Web UI):"
            echo "  Access Kafka UI: http://localhost:8080"
            echo "  IP: 192.168.1.20"
            echo ""
            continue
        fi
        
        local port="${SSH_PORTS[$i]}"
        echo -e "${BLUE}$container${NC} (IP: 192.168.1.$((10 + i))):"
        echo "  Admin user: ssh $ADMIN_USER@localhost -p $port"
        echo "  Root user:  ssh root@localhost -p $port"
        echo "  Password (admin): $ADMIN_PASSWORD"
        echo "  Password (root):  $ROOT_PASSWORD"
        echo ""
    done
    
    print_header "Direct Container Access"
    for container in "${CONTAINERS[@]}"; do
        echo "  docker exec -it $container /bin/bash"
    done
    echo ""
    
    print_header "Network Information"
    if docker network ls | grep -q "kafka-community-8_servers-net"; then
        docker network inspect kafka-community-8_servers-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null || {
            print_warning "Could not retrieve network information"
        }
    else
        print_warning "Network kafka-community-8_servers-net not found"
    fi
}

# Function to test SSH connections
test_ssh_connections() {
    print_header "Testing SSH Connections"
    
    local all_accessible=true
    for i in "${!CONTAINERS[@]}"; do
        local container="${CONTAINERS[$i]}"
        
        # Skip SSH test for kafka-ui since it doesn't have SSH
        if [[ "$container" == "kafka-ui" ]]; then
            print_status "Skipping SSH test for $container (Web UI container)"
            continue
        fi
        
        local port="${SSH_PORTS[$i]}"
        
        if test_ssh_connection "$container" "$port"; then
            print_status "SSH connection test passed for $container on port $port"
        else
            all_accessible=false
        fi
    done
    
    if [ "$all_accessible" = true ]; then
        print_status "All SSH connections are accessible"
        echo ""
        print_header "Test SSH Connection Examples"
        echo "# Test connection with password authentication:"
        for i in "${!CONTAINERS[@]}"; do
            local container="${CONTAINERS[$i]}"
            # Skip SSH examples for kafka-ui
            if [[ "$container" == "kafka-ui" ]]; then
                continue
            fi
            local port="${SSH_PORTS[$i]}"
            echo "ssh -o StrictHostKeyChecking=no $ADMIN_USER@localhost -p $port 'hostname && whoami'"
        done
    else
        print_error "Some SSH connections failed"
        return 1
    fi
}

# Function to setup SSH (without starting containers)
setup_ssh() {
    print_header "Setting up SSH on running containers"
    
    for container in "${CONTAINERS[@]}"; do
        if is_container_running "$container"; then
            configure_ssh "$container"
        else
            print_error "Container $container is not running"
        fi
    done
}

# Function to show logs
show_logs() {
    print_header "Container Logs"
    docker-compose logs --tail=50
}

# Function to stop containers
stop_containers() {
    print_header "Stopping Docker Containers"
    docker-compose down
    print_status "All containers stopped"
}

# Function to cleanup
cleanup() {
    print_header "Cleaning up Docker Environment"
    
    # Clean SSH known_hosts entries before removing containers
    clean_ssh_known_hosts
    
    docker-compose down -v --remove-orphans
    print_status "Cleaned up containers, networks, and volumes"
}

# Function to recreate containers (complete teardown and rebuild)
recreate_containers() {
    print_header "Recreating Docker Containers"
    
    print_status "Stopping and removing existing containers..."
    cleanup
    
    print_status "Recreating containers from scratch..."
    sleep 2
    start_containers
}

# Function to restart containers
restart_containers() {
    print_header "Restarting Docker Containers"
    stop_containers
    sleep 2
    start_containers
}

# Main script logic
case "${1:-}" in
    start)
        start_containers
        echo ""
        show_status
        ;;
    stop)
        stop_containers
        ;;
    restart)
        restart_containers
        echo ""
        show_status
        ;;
    recreate)
        recreate_containers
        echo ""
        show_status
        ;;
    status)
        show_status
        ;;
    ssh-setup)
        setup_ssh
        ;;
    test-ssh)
        test_ssh_connections
        ;;
    logs)
        show_logs
        ;;
    cleanup)
        cleanup
        ;;
    *)
        show_usage
        ;;
esac
