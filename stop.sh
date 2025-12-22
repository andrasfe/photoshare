#!/bin/bash
#
# PhotoShare Client Stop Script
# Stops the Python web client.
#
# Note: The server is managed via the PhotoShare Server app.
#       Use the app's UI or Cmd+Q to stop it.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# PID file
CLIENT_PID_FILE="$SCRIPT_DIR/.client.pid"

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    PhotoShare Client Stop                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

stop_client() {
    if [[ -f "$CLIENT_PID_FILE" ]]; then
        local pid=$(cat "$CLIENT_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${BLUE}Stopping client (PID: $pid)...${NC}"
            kill "$pid" 2>/dev/null
            
            # Wait for graceful shutdown
            for i in {1..10}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null
            fi
            
            echo -e "${GREEN}✓ Client stopped${NC}"
        else
            echo -e "${YELLOW}Client not running${NC}"
        fi
        rm -f "$CLIENT_PID_FILE"
    else
        echo -e "${YELLOW}Client not running (no PID file)${NC}"
    fi
    
    # Also kill any orphaned processes
    local client_pids=$(pgrep -f "run_web.py" 2>/dev/null || true)
    if [[ -n "$client_pids" ]]; then
        echo "Cleaning up orphaned client processes..."
        echo "$client_pids" | xargs kill 2>/dev/null || true
    fi
}

check_server_running() {
    if pgrep -x "PhotoShareServer" > /dev/null 2>&1; then
        return 0
    fi
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

print_status() {
    echo ""
    echo -e "${BLUE}Current Status:${NC}"
    
    if check_server_running; then
        echo -e "  Server: ${GREEN}Running${NC} (use app to stop)"
    else
        echo -e "  Server: ${RED}Stopped${NC}"
    fi
    
    if [[ -f "$CLIENT_PID_FILE" ]] && kill -0 "$(cat "$CLIENT_PID_FILE")" 2>/dev/null; then
        echo -e "  Client: ${GREEN}Running${NC}"
    else
        echo -e "  Client: ${RED}Stopped${NC}"
    fi
    
    echo ""
}

# Main
print_banner
stop_client
print_status
