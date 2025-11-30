#!/bin/bash
# Script to update gitmojis from the official gitmoji API

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITMOJI_FILE="$SCRIPT_DIR/../gitmojis.json"

echo "Fetching gitmojis from https://gitmoji.dev/api/gitmojis..."

# Download and format the gitmojis JSON file
curl -s https://gitmoji.dev/api/gitmojis | jq '.' > "$GITMOJI_FILE"

# Count the emojis
EMOJI_COUNT=$(jq '.gitmojis | length' "$GITMOJI_FILE")

echo "✓ Gitmojis updated successfully!"
echo "$EMOJI_COUNT emojis synchronized from gitmoji.dev"
