#!/bin/bash
# Universal Sync Setup Script
# Usage: ./setup_sync.sh <remote_url> <remote_name>

REMOTE_URL=$1
REMOTE_NAME=$2

if [ -z "$REMOTE_URL" ] || [ -z "$REMOTE_NAME" ]; then
    echo "Usage: ./setup_sync.sh <remote_url> <remote_name>"
    exit 1
fi

echo "Setting up sync channel with $REMOTE_NAME..."

# Check if remote exists, if not add it
if git remote | grep -q "$REMOTE_NAME"; then
    echo "Remote '$REMOTE_NAME' already exists. Updating URL..."
    git remote set-url "$REMOTE_NAME" "$REMOTE_URL"
else
    git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

# Fetch latest changes
git fetch "$REMOTE_NAME"
echo "Sync channel established successfully."
