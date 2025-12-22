#!/bin/bash
#
# PhotoShare Status Script
# Shows status of server app and client services.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# PID file
CLIENT_PID_FILE="$SCRIPT_DIR/.client.pid"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      PhotoShare Status                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Server status (app-based)
echo -e "${CYAN}Server (PhotoShare Server App):${NC}"
server_pid=$(pgrep -x "PhotoShareServer" 2>/dev/null || pgrep -x "PhotoShareServe" 2>/dev/null)
if [[ -n "$server_pid" ]]; then
    echo -e "  Status:  ${GREEN}● Running${NC} (PID: $server_pid)"
    echo -e "  URL:     http://localhost:8080"
    health=$(curl -s http://localhost:8080/health 2>/dev/null)
    if [[ "$health" == "OK" ]]; then
        echo -e "  Health:  ${GREEN}OK${NC}"
    else
        echo -e "  Health:  ${YELLOW}Starting...${NC}"
    fi
else
    echo -e "  Status:  ${RED}● Not running${NC}"
    echo -e "  ${YELLOW}→ Launch the PhotoShare Server app to start${NC}"
fi

echo ""

# Client status
echo -e "${CYAN}Web Client:${NC}"
if [[ -f "$CLIENT_PID_FILE" ]]; then
    pid=$(cat "$CLIENT_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "  Status:  ${GREEN}● Running${NC} (PID: $pid)"
        echo -e "  URL:     http://localhost:8000"
        
        # Check if it can reach the server
        health=$(curl -s http://localhost:8000/api/health 2>/dev/null)
        if [[ -n "$health" ]]; then
            server_healthy=$(echo "$health" | python3 -c "import sys,json; print(json.load(sys.stdin).get('server_healthy', False))" 2>/dev/null)
            if [[ "$server_healthy" == "True" ]]; then
                echo -e "  Server:  ${GREEN}Connected${NC}"
            else
                echo -e "  Server:  ${YELLOW}Disconnected${NC}"
            fi
        fi
    else
        echo -e "  Status:  ${RED}● Stopped${NC} (stale PID file)"
    fi
else
    echo -e "  Status:  ${RED}● Stopped${NC}"
fi

echo ""

# Quick commands
echo -e "${CYAN}Commands:${NC}"
echo -e "  Start client:  ${YELLOW}./start.sh${NC}"
echo -e "  Stop client:   ${YELLOW}./stop.sh${NC}"
echo -e "  Start server:  ${YELLOW}Open PhotoShare Server app${NC}"
echo ""

# How to build server app
if [[ ! -f "$SCRIPT_DIR/server-app/.build/debug/PhotoShareServer" ]]; then
    echo -e "${CYAN}Build server app:${NC}"
    echo -e "  ${BLUE}cd server-app && swift build${NC}"
    echo ""
fi
