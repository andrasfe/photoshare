#!/bin/bash
#
# PhotoShare Client Launcher
# Starts the Python web client for syncing photos.
#
# Note: The server is managed via the PhotoShare Server app (server-app/).
#       Build and run it with: cd server-app && swift build && .build/debug/PhotoShareServer
#
# Usage:
#   ./start.sh           # Start the web client
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$SCRIPT_DIR/client"
SERVER_APP_DIR="$SCRIPT_DIR/server-app"

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
    echo "║                   PhotoShare Client Launcher                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_client_requirements() {
    if [[ ! -d "$CLIENT_DIR" ]]; then
        echo -e "${RED}Client directory not found${NC}"
        return 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}⚠ Python 3 not found.${NC}"
        return 1
    fi
    
    return 0
}

check_server_running() {
    # Check if server app is running
    if pgrep -x "PhotoShareServer" > /dev/null 2>&1; then
        return 0
    fi
    
    # Check if old CLI server is running
    if pgrep -f "swift run" > /dev/null 2>&1; then
        return 0
    fi
    
    # Check if port 8080 is responding
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

start_client() {
    if [[ -f "$CLIENT_PID_FILE" ]]; then
        local pid=$(cat "$CLIENT_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Client already running (PID: $pid)${NC}"
            return 0
        fi
    fi
    
    echo -e "${BLUE}Starting web client...${NC}"
    cd "$CLIENT_DIR"
    
    # Create venv if needed
    if [[ ! -d "venv" ]]; then
        echo "Creating Python virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate and install deps
    source venv/bin/activate
    pip install -q -r requirements.txt 2>/dev/null
    
    # Run in background
    python run_web.py &> "$SCRIPT_DIR/.client.log" &
    local pid=$!
    echo $pid > "$CLIENT_PID_FILE"
    
    # Wait for client to start
    sleep 2
    
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}✓ Web client started on http://localhost:8000 (PID: $pid)${NC}"
        return 0
    else
        echo -e "${RED}✗ Client failed to start. Check .client.log for details.${NC}"
        rm -f "$CLIENT_PID_FILE"
        return 1
    fi
}

print_status() {
    echo ""
    echo -e "${BLUE}Services:${NC}"
    
    if check_server_running; then
        echo -e "  Server: ${GREEN}Running${NC} (via PhotoShare Server app)"
    else
        echo -e "  Server: ${YELLOW}Not running${NC}"
        echo -e "          ${YELLOW}→ Launch PhotoShare Server app to start${NC}"
    fi
    
    if [[ -f "$CLIENT_PID_FILE" ]] && kill -0 "$(cat "$CLIENT_PID_FILE")" 2>/dev/null; then
        echo -e "  Client: ${GREEN}Running${NC} at http://localhost:8000"
    else
        echo -e "  Client: ${RED}Stopped${NC}"
    fi
    
    echo ""
    echo -e "Run ${YELLOW}./stop.sh${NC} to stop the client"
    echo -e "Use the ${YELLOW}PhotoShare Server app${NC} to control the server"
}

# Main
print_banner

# Check if server is running
if ! check_server_running; then
    echo -e "${YELLOW}⚠ Server is not running!${NC}"
    echo ""
    echo -e "To start the server, launch the PhotoShare Server app:"
    echo -e "  ${BLUE}cd server-app && swift build && open .build/debug/PhotoShareServer${NC}"
    echo -e "  Or double-click the app if you've built it."
    echo ""
    echo -e "Starting client anyway (it will connect when server is available)..."
    echo ""
fi

if check_client_requirements; then
    start_client
else
    echo -e "${RED}Client requirements not met${NC}"
    exit 1
fi

print_status
