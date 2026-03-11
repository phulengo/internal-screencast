#!/usr/bin/env bash
#
# Internal Screencast — Quick Start
# Starts the signaling server and serves the receiver page.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNALING_PORT=8765
RECEIVER_PORT=8080

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get LAN IP
get_lan_ip() {
    if command -v ip &>/dev/null; then
        ip route get 1 2>/dev/null | awk '{print $7; exit}'
    elif command -v ifconfig &>/dev/null; then
        ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}'
    else
        hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
    fi
}

LAN_IP=$(get_lan_ip)

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║       Internal Screencast                ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Check Python
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required. Install Python 3.8+."
    exit 1
fi

# Install dependencies
echo "Checking Python dependencies..."
pip3 install -q -r "$SCRIPT_DIR/signaling/requirements.txt" 2>/dev/null || {
    echo -e "${YELLOW}Warning: Could not install via pip3. Install manually: pip3 install websockets${NC}"
}

# Start signaling server
echo "Starting signaling server on port $SIGNALING_PORT..."
python3 "$SCRIPT_DIR/signaling/server.py" --port "$SIGNALING_PORT" &
SIGNALING_PID=$!

# Start receiver HTTP server
echo "Starting receiver on port $RECEIVER_PORT..."
python3 -m http.server "$RECEIVER_PORT" --directory "$SCRIPT_DIR/receiver" &
RECEIVER_PID=$!

# Cleanup on exit
cleanup() {
    echo ""
    echo "Shutting down..."
    kill "$SIGNALING_PID" 2>/dev/null || true
    kill "$RECEIVER_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

echo ""
echo -e "${GREEN}Ready!${NC}"
echo ""
echo "  Signaling server:  ws://$LAN_IP:$SIGNALING_PORT"
echo "  Receiver URL:      http://$LAN_IP:$RECEIVER_PORT"
echo ""
echo "Steps:"
echo "  1. Open the receiver URL on your TV browser"
echo "  2. Open Internal Screencast app on your iPhone"
echo "  3. Enter this IP: $LAN_IP"
echo "  4. Tap the broadcast button to start mirroring"
echo ""
echo "  Press S on the TV to toggle stats overlay"
echo "  Press F on the TV to toggle fullscreen"
echo ""
echo "Press Ctrl+C to stop."
echo ""

# Wait for background processes
wait
