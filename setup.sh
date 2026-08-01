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
    # k6: real load-test gate with thresholds
    if ! command -v k6 &>/dev/null; then
        curl -s https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
        sudo apt-get update -qq
        sudo apt-get install -y -qq k6
    fi
}

install_centos() {
    log "Install dependencies (CentOS/RHEL)..."
    sudo yum install -y bc curl mysql mongosh nmap-ncat
    if ! command -v k6 &>/dev/null; then
        sudo dnf install -y https://dl.k6.io/rpm/repo.rpm
        sudo dnf install -y k6
    fi
}

install_macos() {
    log "Install dependencies (macOS)..."
    if ! command -v brew &>/dev/null; then
        err "Homebrew not found. Install from https://brew.sh"
        exit 1
    fi
    brew install bc curl mysql-client mongosh
    brew install k6 || warn "k6 install via brew failed; install manually from https://k6.io"
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

setup_stress_tool() {
    if [ -f ./stress-tool ]; then
        log "  stress-tool already present"
        return 0
    fi
    if [ -n "${STRESS_TOOL_URL:-}" ]; then
        log "  Fetching stress-tool from STRESS_TOOL_URL..."
        curl -sL "${STRESS_TOOL_URL}" -o ./stress-tool && chmod +x ./stress-tool \
            && log "  stress-tool installed" \
            || warn "  failed to download stress-tool from ${STRESS_TOOL_URL}"
    else
        warn "  stress-tool not installed. The auto-drive (--mode send/recv) and"
        warn "  cluster node tests will skip; use --mode verify with MEASURED_* env"
        warn "  vars, or set STRESS_TOOL_URL and re-run setup.sh."
    fi
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
            setup_stress_tool

            log ""
            log "Setup complete. Run tests with:"
            log "  bash performance/run_single_chat_test.sh check"
            log "  k6 run -e IM_HOST=<host> -e IM_PORT=80 performance/k6_single_chat.js"
            log "  # For benchmark assertion without stress-tool, feed measured values:"
            log "  RATE=19646 TOTAL=... SUCCESS=100 bash performance/run_single_chat_test.sh --mode verify"
            log "  # Self-test without a real IM server using the bundled mock:"
            log "  python3 ci/mock_im_server.py 18080 &"
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
