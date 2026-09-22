#!/bin/bash
# Starts the shared SQL Server container and the drift-tool Flask app, then
# opens the browser. Ctrl+C (or closing this terminal) stops the app.
set -e
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")"

echo "Starting SQL Server container (drift-tool-mssql, shared with the chatbot)..."
docker start drift-tool-mssql >/dev/null 2>&1 || echo "  (couldn't start it -- check 'docker ps -a')"

echo "Starting drift-tool on :5057..."
python3.13 app.py &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null' EXIT

sleep 2
xdg-open http://localhost:5057 >/dev/null 2>&1 &

echo ""
echo "Olives DB Drift Tool running at http://localhost:5057"
echo "Press Ctrl+C to stop."
wait
