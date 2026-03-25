#!/bin/bash
# Start script for Paloma Morse Engine

# Navigate to the project directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "Stopping previous instances..."
killall node 2>/dev/null
killall morze_app 2>/dev/null

echo "Starting Morse Bridge & Engine..."
# Start the bridge in the background
# The bridge automatically spawns ./morze_app
node ui/bridge.cjs > bridge.log 2>&1 &

echo "Starting UI Dev Server..."
npm run dev --prefix ui > ui.log 2>&1 &

echo "------------------------------------------------"
echo "PALOMA MORSE SYSTEM STARTED!"
echo "UI: http://localhost:5173 (or 5174)"
echo "Logs: bridge.log, ui.log"
echo "------------------------------------------------"
