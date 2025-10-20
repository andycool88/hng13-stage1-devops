Docker Deployment Script
One-command automated deployment for Dockerized applications to remote servers.

Quick Start
1. Setup Script
bash
chmod +x deploy.sh
2. Run Deployment
bash
./deploy.sh
3. Provide Information When Prompted:
GitHub Repository URL

GitHub Personal Access Token

Server IP & SSH Username

Application Port (default: 8080)

What It Does Automatically
✅ Clones your code from GitHub
✅ Sets up remote server with Docker & Nginx
✅ Deploys your app in Docker containers
✅ Configures reverse proxy for web access
✅ Runs health checks and validation

Prerequisites
Remote Linux server (Ubuntu/CentOS) with SSH access

GitHub repo with Dockerfile or docker-compose.yml

GitHub Personal Access Token with repo permissions

Example Usage
bash
$ ./deploy.sh
Enter Git Repository: https://github.com/yourname/yourapp.git
Enter PAT: ghp_yourtoken123
Enter server IP: 192.168.1.100
Enter username: ubuntu
Enter port [8080]: 3000
Result: Your app runs at http://192.168.1.100

Troubleshooting
Check generated log files: deploy_YYYYMMDD_HHMMSS.log

Verify SSH key permissions: chmod 600 your-key.pem

Test manually: ssh user@server "docker ps"

Deploy in one command. No complex setup required. 🎯
