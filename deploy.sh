#!/bin/bash

# =============================================
# AUTOMATED DOCKER DEPLOYMENT SCRIPT
# Version: 1.0
# Description: Deploys Dockerized apps to remote servers
# Author : Emaye Olugbenga Andrew
# =============================================

# Set strict error handling
set -euo pipefail

# Global variables
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
GIT_REPO_URL=""
GIT_PAT=""
BRANCH_NAME="main"
REMOTE_USER=""
SERVER_IP=""
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
APP_PORT="8080"
REPO_NAME=""

# Initialize logging
setup_logging() {
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    echo "=== Deployment started at $(date) ==="
    echo "Log file: $LOG_FILE"
}

# Error handler
error_handler() {
    echo "ERROR: Script failed at line $LINENO. Check $LOG_FILE for details."
    exit 1
}

trap error_handler ERR

# Function to collect and validate user input
collect_parameters() {
    echo "=== Collecting Deployment Parameters ==="
    
    # Git Repository details
    read -p "Enter Git Repository URL: " GIT_REPO_URL
    if [[ -z "$GIT_REPO_URL" ]]; then
        echo "ERROR: Git Repository URL is required!"
        exit 1
    fi
    
    read -p "Enter Personal Access Token (PAT): " GIT_PAT
    if [[ -z "$GIT_PAT" ]]; then
        echo "ERROR: Personal Access Token is required!"
        exit 1
    fi
    
    read -p "Enter branch name [main]: " BRANCH_NAME
    BRANCH_NAME=${BRANCH_NAME:-main}
    
    # SSH connection details
    read -p "Enter remote server username: " REMOTE_USER
    if [[ -z "$REMOTE_USER" ]]; then
        echo "ERROR: Remote server username is required!"
        exit 1
    fi
    
    read -p "Enter remote server IP address: " SERVER_IP
    if [[ -z "$SERVER_IP" ]]; then
        echo "ERROR: Server IP address is required!"
        exit 1
    fi
    
    read -p "Enter SSH key path [$HOME/.ssh/id_rsa]: " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}
    
    # Application port
    read -p "Enter application port [8080]: " APP_PORT
    APP_PORT=${APP_PORT:-8080}
    
    # Validate SSH key exists
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        echo "ERROR: SSH key not found at $SSH_KEY_PATH"
        exit 1
    fi
    
    # Set proper permissions for SSH key
    chmod 600 "$SSH_KEY_PATH"
    
    echo "Parameters collected successfully!"
}

# Function to handle git operations
git_operations() {
    echo "=== Handling Git Repository ==="
    
    # Extract repo name from URL for folder name
    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    echo "Repository name: $REPO_NAME"
    
    if [[ -d "$REPO_NAME" ]]; then
        echo "Repository exists, pulling latest changes..."
        cd "$REPO_NAME"
        
        # Use PAT for authentication
        git pull https://$GIT_PAT@${GIT_REPO_URL#*//}
    else
        echo "Cloning new repository..."
        # Clone using PAT authentication
        git clone https://$GIT_PAT@${GIT_REPO_URL#*//}
        cd "$REPO_NAME"
    fi
    
    # Switch to specified branch
    echo "Switching to branch: $BRANCH_NAME"
    git checkout "$BRANCH_NAME"
    
    echo "Git operations completed successfully!"
}

# Function to verify Docker configuration
verify_docker_config() {
    echo "=== Verifying Docker Configuration ==="
    
    if [[ -f "Dockerfile" ]]; then
        echo "✓ Dockerfile found"
        DOCKER_CONFIG="Dockerfile"
    elif [[ -f "docker-compose.yml" ]]; then
        echo "✓ docker-compose.yml found"
        DOCKER_CONFIG="compose"
    else
        echo "ERROR: No Dockerfile or docker-compose.yml found!"
        echo "Please ensure your project has Docker configuration."
        exit 1
    fi
    
    echo "Docker configuration verified!"
}

# Function to test SSH connection
test_ssh_connection() {
    echo "Testing SSH connection to $REMOTE_USER@$SERVER_IP..."
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" "echo '✓ SSH connection successful'"; then
        echo "ERROR: SSH connection failed!"
        exit 1
    fi
}

# Function to setup remote server
setup_remote_server() {
    echo "=== Setting up Remote Server ==="
    
    test_ssh_connection
    
    # Execute setup commands on remote server
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" << 'EOF'
        set -e
        echo "Updating system packages..."
        sudo apt-get update -y
        
        echo "Installing Docker..."
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
        fi
        
        echo "Installing Docker Compose..."
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi
        
        echo "Installing Nginx..."
        if ! command -v nginx &> /dev/null; then
            sudo apt-get install -y nginx
        fi
        
        echo "Starting and enabling services..."
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        echo "✓ Remote server setup completed!"
EOF
}

# Function to transfer files to remote server
transfer_files() {
    echo "=== Transferring Project Files ==="
    
    # Create directory on remote server
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" "mkdir -p ~/app"
    
    # Transfer files
    echo "Copying project files to remote server..."
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -r . "$REMOTE_USER@$SERVER_IP:~/app/"
    
    echo "✓ File transfer completed!"
}

# Function to deploy application
deploy_application() {
    echo "=== Deploying Application ==="
    
    # Execute deployment on remote server
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" << EOF
        set -e
        
        cd ~/app
        
        echo "Building and running Docker containers..."
        
        if [[ -f "docker-compose.yml" ]]; then
            echo "Using docker-compose..."
            sudo docker-compose down || true
            sudo docker-compose up -d --build
        elif [[ -f "Dockerfile" ]]; then
            echo "Using Dockerfile..."
            # Stop existing container if running
            sudo docker stop app-container || true
            sudo docker rm app-container || true
            
            # Build and run new container
            sudo docker build -t my-app .
            sudo docker run -d --name app-container -p $APP_PORT:$APP_PORT my-app
        fi
        
        echo "Waiting for containers to start..."
        sleep 10
        
        echo "Checking container status..."
        sudo docker ps
        
        echo "✓ Application deployment completed!"
EOF
}

# Function to configure Nginx
configure_nginx() {
    echo "=== Configuring Nginx Reverse Proxy ==="
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" << EOF
        set -e
        
        echo "Creating Nginx configuration..."
        sudo bash -c 'cat > /etc/nginx/sites-available/app << NGINXCFG
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
NGINXCFG'
        
        # Enable the site
        sudo ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
        
        # Remove default site if exists
        sudo rm -f /etc/nginx/sites-enabled/default
        
        echo "Testing Nginx configuration..."
        sudo nginx -t
        
        echo "Reloading Nginx..."
        sudo systemctl reload nginx
        
        echo "✓ Nginx configuration completed!"
EOF
}

# Function to validate deployment
validate_deployment() {
    echo "=== Validating Deployment ==="
    
    echo "1. Checking Docker services..."
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" "sudo systemctl is-active docker"
    
    echo "2. Checking container status..."
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" "sudo docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"
    
    echo "3. Checking Nginx status..."
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" "sudo systemctl is-active nginx"
    
    echo "4. Testing application endpoint..."
    if curl -f -s --connect-timeout 10 "http://$SERVER_IP" > /dev/null; then
        echo "✓ SUCCESS: Application is accessible at http://$SERVER_IP"
    else
        echo "⚠ WARNING: Application might not be fully ready yet"
        echo "You may need to wait a few moments and refresh http://$SERVER_IP"
    fi
}

# Function for cleanup
cleanup() {
    echo "=== Cleanup ==="
    read -p "Do you want to remove old containers and images? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER_IP" << 'EOF'
            echo "Cleaning up unused Docker resources..."
            sudo docker system prune -f
            echo "✓ Cleanup completed!"
EOF
    fi
}

# Display success message
show_success() {
    echo ""
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    echo "🌐 Your application is running at: http://$SERVER_IP"
    echo "📋 Log file: $LOG_FILE"
    echo ""
    echo "Next steps:"
    echo "1. Open http://$SERVER_IP in your browser"
    echo "2. Check logs if needed: cat $LOG_FILE"
    echo "3. To redeploy: simply run ./deploy.sh again"
    echo "=========================================="
}

# Main execution function
main() {
    echo "🚀 Starting Automated Docker Deployment..."
    echo ""
    
    setup_logging
    collect_parameters
    git_operations
    verify_docker_config
    setup_remote_server
    transfer_files
    deploy_application
    configure_nginx
    validate_deployment
    cleanup
    show_success
}

# Run main function
main "$@"
