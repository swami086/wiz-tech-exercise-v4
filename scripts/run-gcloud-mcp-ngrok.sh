#!/usr/bin/env bash
# Expose gcloud MCP server over SSE via supergateway, then tunnel with ngrok.
# Cursor mcp.json is not modified; external clients connect to the ngrok SSE URL.
#
# Usage:
#   Terminal 1: ./scripts/run-gcloud-mcp-ngrok.sh
#   Terminal 2: ngrok http 9090   # then use the https://...ngrok-free.dev URL
#
# Or run both in background (supergateway first, then ngrok).
PORT=${1:-9090}
echo "Starting supergateway (gcloud-mcp → SSE) on port $PORT..."
exec npx -y supergateway --port "$PORT" --stdio "npx -y @google-cloud/gcloud-mcp" --cors --logLevel info
