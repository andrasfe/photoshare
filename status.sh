#!/bin/bash
#
# PhotoShare Status Script
# Shows status of server and client services.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# PID files
SERVER_PID_FILE="$SCRIPT_DIR/.server.pid"
CLIENT_PID_FILE="$SCRIPT_DIR/.client.pid"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      PhotoShare Status                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Server status
echo -e "${CYAN}Server:${NC}"
if [[ -f "$SERVER_PID_FILE" ]]; then
    pid=$(cat "$SERVER_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "  Status:  ${GREEN}● Running${NC} (PID: $pid)"
        echo -e "  URL:     http://localhost:8080"
        echo -e "  Health:  $(curl -s http://localhost:8080/health 2>/dev/null || echo 'Unable to connect')"
    else
        echo -e "  Status:  ${RED}● Stopped${NC} (stale PID file)"
    fi
else
    echo -e "  Status:  ${RED}● Stopped${NC}"
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

# System info
echo -e "${CYAN}System:${NC}"
echo -e "  OS:      $(uname -s) $(uname -r)"
echo -e "  Swift:   $(swift --version 2>/dev/null | head -1 || echo 'Not installed')"
echo -e "  Python:  $(python3 --version 2>/dev/null || echo 'Not installed')"

echo ""
echo -e "Commands: ${YELLOW}./start.sh${NC} | ${YELLOW}./stop.sh${NC} | ${YELLOW}./status.sh${NC}"

