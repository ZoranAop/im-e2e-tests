#!/usr/bin/env bash
# ============================================================
# IM E2E Test Environment Setup
# ============================================================
# Usage: bash setup.sh [--docker] [--local]
#   --docker  Start test dependencies via Docker Compose
#   --local   Install dependencies locally
# ============================================================

set -euo pipefail

MODE="${1:---local}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

check_cmd() {
    if command -v "$1" &>/dev/null; then
        log "  $1: installed"
        return 0
    else
        warn "  $1: NOT installed"
        return 1
    fi
}

install_ubuntu() {
    log "Install dependencies (Ubuntu/Debian)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq bc curl mysql-client mongosh netcat-openbsd
}

install_centos() {
    log "Install dependencies (CentOS/RHEL)..."
    sudo yum install -y bc curl mysql mongosh nmap-ncat
}

install_macos() {
    log "Install dependencies (macOS)..."
    if ! command -v brew &>/dev/null; then
        err "Homebrew not found. Install from https://brew.sh"
        exit 1
    fi
    brew install bc curl mysql-client mongosh
}

setup_env() {
    log "Configure environment..."
    if [ ! -f .env ]; then
        cp .env.example .env
        log "  Created .env from .env.example"
        warn "  Edit .env with your IM server settings"
    else
        log "  .env already exists"
    fi

    # Load env
    set -a; source .env 2>/dev/null || true; set +a

    mkdir -p reports
    log "  Created reports/ directory"
}

setup_docker() {
    log "Start test infrastructure via Docker..."
    if ! command -v docker &>/dev/null; then
        err "Docker not found"
        exit 1
    fi
    
    if [ -f docker-compose.test.yml ]; then
        docker compose -f docker-compose.test.yml up -d
        log "  MySQL: localhost:3306 (root/testpass123, db=imdb)"
        log "  MongoDB: localhost:27017"
        
        echo ""
        log "Waiting for services to be ready..."
        sleep 10
        
        if docker compose -f docker-compose.test.yml ps | grep -q "Up"; then
            log "Services are running."
        else
            err "Services failed to start. Check: docker compose -f docker-compose.test.yml logs"
        fi
    else
        err "docker-compose.test.yml not found"
    fi
}

main() {
    echo ""
    echo "============================================================"
    echo "  IM E2E Test Environment Setup"
    echo "============================================================"
    echo ""

    case "${MODE}" in
        --docker|-d)
            setup_env
            setup_docker
            ;;
        --local|-l)
            log "Check prerequisites..."
            check_cmd bash
            check_cmd bc
            check_cmd curl
            check_cmd mysql || warn "mysql client recommended for DB validation"
            check_cmd mongosh || warn "mongosh recommended for MongoDB validation"
            
            setup_env
            
            log ""
            log "Setup complete. Run tests with:"
            log "  bash performance/run_single_chat_test.sh check"
            ;;
        *)
            echo "Usage: bash setup.sh [--docker | --local]"
            exit 1
            ;;
    esac
    
    echo ""
    log "Done."
}

main
