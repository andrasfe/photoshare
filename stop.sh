#!/bin/bash
#
# PhotoShare Stop Script
# Stops server and/or client services.
#
# Usage:
#   ./stop.sh           # Stop all running components
#   ./stop.sh server    # Stop server only
#   ./stop.sh client    # Stop client only
#   ./stop.sh web       # Stop web client only (alias for client)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# PID files
SERVER_PID_FILE="$SCRIPT_DIR/.server.pid"
CLIENT_PID_FILE="$SCRIPT_DIR/.client.pid"

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                       PhotoShare Stop                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

stop_server() {
    if [[ -f "$SERVER_PID_FILE" ]]; then
        local pid=$(cat "$SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${BLUE}Stopping server (PID: $pid)...${NC}"
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
            
            echo -e "${GREEN}✓ Server stopped${NC}"
        else
            echo -e "${YELLOW}Server not running${NC}"
        fi
        rm -f "$SERVER_PID_FILE"
    else
        echo -e "${YELLOW}Server not running (no PID file)${NC}"
    fi
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
}

stop_by_process() {
    # Fallback: find and kill by process name
    echo -e "${BLUE}Checking for orphaned processes...${NC}"
    
    local server_pids=$(pgrep -f "swift run" 2>/dev/null || true)
    if [[ -n "$server_pids" ]]; then
        echo "Found server processes: $server_pids"
        echo "$server_pids" | xargs kill 2>/dev/null || true
    fi
    
    local client_pids=$(pgrep -f "run_web.py" 2>/dev/null || true)
    if [[ -n "$client_pids" ]]; then
        echo "Found client processes: $client_pids"
        echo "$client_pids" | xargs kill 2>/dev/null || true
    fi
}

print_status() {
    echo ""
    echo -e "${BLUE}Current Status:${NC}"
    
    local server_running=false
    local client_running=false
    
    if [[ -f "$SERVER_PID_FILE" ]] && kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null; then
        server_running=true
    fi
    
    if [[ -f "$CLIENT_PID_FILE" ]] && kill -0 "$(cat "$CLIENT_PID_FILE")" 2>/dev/null; then
        client_running=true
    fi
    
    if $server_running; then
        echo -e "  Server: ${GREEN}Running${NC}"
    else
        echo -e "  Server: ${RED}Stopped${NC}"
    fi
    
    if $client_running; then
        echo -e "  Client: ${GREEN}Running${NC}"
    else
        echo -e "  Client: ${RED}Stopped${NC}"
    fi
    
    echo ""
}

# Main
print_banner

case "${1:-all}" in
    server)
        stop_server
        ;;
    client|web)
        stop_client
        ;;
    all|"")
        stop_server
        stop_client
        stop_by_process
        ;;
    status)
        print_status
        exit 0
        ;;
    *)
        echo "Usage: $0 [server|client|web|all|status]"
        exit 1
        ;;
esac

print_status

