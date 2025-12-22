#!/bin/bash
#
# PhotoShare Launcher
# Starts server and/or client based on what's available on this computer.
#
# Usage:
#   ./start.sh           # Start all available components
#   ./start.sh server    # Start server only
#   ./start.sh client    # Start client only
#   ./start.sh web       # Start web client only (alias for client)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
CLIENT_DIR="$SCRIPT_DIR/client"

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
    echo "║                      PhotoShare Launcher                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_server_requirements() {
    if [[ ! -d "$SERVER_DIR" ]]; then
        return 1
    fi
    
    # Check if we're on macOS (required for PhotoKit)
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${YELLOW}⚠ Server requires macOS for Photos library access${NC}"
        return 1
    fi
    
    # Check for Swift
    if ! command -v swift &> /dev/null; then
        echo -e "${YELLOW}⚠ Swift not found. Install Xcode Command Line Tools.${NC}"
        return 1
    fi
    
    return 0
}

check_client_requirements() {
    if [[ ! -d "$CLIENT_DIR" ]]; then
        return 1
    fi
    
    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}⚠ Python 3 not found.${NC}"
        return 1
    fi
    
    return 0
}

start_server() {
    if [[ -f "$SERVER_PID_FILE" ]]; then
        local pid=$(cat "$SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Server already running (PID: $pid)${NC}"
            return 0
        fi
    fi
    
    echo -e "${BLUE}Starting server...${NC}"
    cd "$SERVER_DIR"
    
    # Build first
    echo "Building Swift server..."
    swift build 2>&1 | tail -5
    
    # Run in background
    swift run &> "$SCRIPT_DIR/.server.log" &
    local pid=$!
    echo $pid > "$SERVER_PID_FILE"
    
    # Wait for server to start
    sleep 3
    
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}✓ Server started on http://localhost:8080 (PID: $pid)${NC}"
        return 0
    else
        echo -e "${RED}✗ Server failed to start. Check .server.log for details.${NC}"
        rm -f "$SERVER_PID_FILE"
        return 1
    fi
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
    
    if [[ -f "$SERVER_PID_FILE" ]] && kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null; then
        echo -e "  Server: ${GREEN}Running${NC} at http://localhost:8080"
    else
        echo -e "  Server: ${RED}Stopped${NC}"
    fi
    
    if [[ -f "$CLIENT_PID_FILE" ]] && kill -0 "$(cat "$CLIENT_PID_FILE")" 2>/dev/null; then
        echo -e "  Client: ${GREEN}Running${NC} at http://localhost:8000"
    else
        echo -e "  Client: ${RED}Stopped${NC}"
    fi
    
    echo ""
    echo -e "Run ${YELLOW}./stop.sh${NC} to stop services"
}

# Main
print_banner

case "${1:-all}" in
    server)
        if check_server_requirements; then
            start_server
        else
            echo -e "${RED}Server requirements not met${NC}"
            exit 1
        fi
        ;;
    client|web)
        if check_client_requirements; then
            start_client
        else
            echo -e "${RED}Client requirements not met${NC}"
            exit 1
        fi
        ;;
    all|"")
        started=0
        
        if check_server_requirements; then
            start_server && ((started++))
        else
            echo -e "${YELLOW}Skipping server (not available on this system)${NC}"
        fi
        
        if check_client_requirements; then
            start_client && ((started++))
        else
            echo -e "${YELLOW}Skipping client (not available on this system)${NC}"
        fi
        
        if [[ $started -eq 0 ]]; then
            echo -e "${RED}No components could be started${NC}"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [server|client|web|all]"
        exit 1
        ;;
esac

print_status

