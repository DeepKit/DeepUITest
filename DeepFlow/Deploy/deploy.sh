#!/bin/bash
# UniFlow Deployment Script
# TASK-2003: 生产部署脚本
#
# 使用方法:
#   ./deploy.sh [command]
#
# Commands:
#   start       - 启动所有服�?
#   stop        - 停止所有服�?
#   restart     - 重启所有服�?
#   status      - 查看服务状�?
#   logs        - 查看日志
#   health      - 健康检�?
#   build       - 构建镜像
#   pull        - 拉取镜像
#   clean       - 清理资源
#   monitoring  - 启动监控服务

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
PROJECT_NAME="uniflow"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    if [ ! -f ".env" ]; then
        log_warning ".env file not found, copying from .env.example"
        cp .env.example .env
        log_warning "Please edit .env with your configuration"
    fi
    
    log_success "All requirements met"
}

cmd_start() {
    log_info "Starting UniFlow services..."
    check_requirements
    
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d
    
    log_info "Waiting for services to be healthy..."
    sleep 10
    
    cmd_health
    
    log_success "UniFlow services started"
}

cmd_stop() {
    log_info "Stopping UniFlow services..."
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME down
    log_success "UniFlow services stopped"
}

cmd_restart() {
    log_info "Restarting UniFlow services..."
    cmd_stop
    cmd_start
}

cmd_status() {
    log_info "Service status:"
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME ps
}

cmd_logs() {
    SERVICE=${2:-""}
    if [ -n "$SERVICE" ]; then
        docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME logs -f $SERVICE
    else
        docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME logs -f
    fi
}

cmd_health() {
    log_info "Running health checks..."
    
    # Check Python Skills
    echo -n "  Python Skills: "
    if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
        echo -e "${GREEN}Healthy${NC}"
    else
        echo -e "${RED}Unhealthy${NC}"
    fi
    
    # Check Node.js Skills
    echo -n "  Node.js Skills: "
    if curl -sf http://localhost:3001/health > /dev/null 2>&1; then
        echo -e "${GREEN}Healthy${NC}"
    else
        echo -e "${RED}Unhealthy${NC}"
    fi
    
    # Check Nginx
    echo -n "  Nginx: "
    if curl -sf http://localhost/health > /dev/null 2>&1; then
        echo -e "${GREEN}Healthy${NC}"
    else
        echo -e "${RED}Unhealthy${NC}"
    fi
}

cmd_build() {
    log_info "Building Docker images..."
    check_requirements
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME build
    log_success "Images built successfully"
}

cmd_pull() {
    log_info "Pulling Docker images..."
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME pull
    log_success "Images pulled successfully"
}

cmd_clean() {
    log_info "Cleaning up resources..."
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME down -v --remove-orphans
    docker system prune -f
    log_success "Cleanup completed"
}

cmd_monitoring() {
    log_info "Starting monitoring services..."
    check_requirements
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME --profile monitoring up -d
    log_success "Monitoring services started"
    log_info "Grafana: http://localhost:3000"
    log_info "Prometheus: http://localhost:9090"
}

cmd_backup() {
    log_info "Creating backup..."
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    # Backup volumes
    docker run --rm -v uniflow_skills-python-data:/data -v $(pwd)/$BACKUP_DIR:/backup alpine tar czf /backup/skills-python-data.tar.gz -C /data .
    docker run --rm -v uniflow_skills-nodejs-data:/data -v $(pwd)/$BACKUP_DIR:/backup alpine tar czf /backup/skills-nodejs-data.tar.gz -C /data .
    
    log_success "Backup created in $BACKUP_DIR"
}

cmd_help() {
    echo "UniFlow Deployment Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start       - Start all services"
    echo "  stop        - Stop all services"
    echo "  restart     - Restart all services"
    echo "  status      - Show service status"
    echo "  logs [svc]  - Show logs (optionally for specific service)"
    echo "  health      - Run health checks"
    echo "  build       - Build Docker images"
    echo "  pull        - Pull Docker images"
    echo "  clean       - Clean up resources"
    echo "  monitoring  - Start monitoring services"
    echo "  backup      - Create backup"
    echo "  help        - Show this help"
}

# Main
case "${1:-help}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs "$@"
        ;;
    health)
        cmd_health
        ;;
    build)
        cmd_build
        ;;
    pull)
        cmd_pull
        ;;
    clean)
        cmd_clean
        ;;
    monitoring)
        cmd_monitoring
        ;;
    backup)
        cmd_backup
        ;;
    help|*)
        cmd_help
        ;;
esac
