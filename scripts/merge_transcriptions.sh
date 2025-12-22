#!/usr/bin/env bash
#
# merge_transcriptions.sh - Merges partial transcriptions into one file
#
# Usage: ./merge_transcriptions.sh <transcriptions_dir> <output_file>
#

set -euo pipefail

ADD_MARKERS="${ADD_MARKERS:-false}"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <transcriptions_directory> <output_file>"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_FILE="$2"

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory not found: $INPUT_DIR"
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "=========================================="
echo "Merging transcriptions"
echo "=========================================="

TRANSCRIPTIONS=$(find "$INPUT_DIR" -type f \( -name "*.txt" -o -name "*.json" \) ! -name ".*" | sort)
FILE_COUNT=$(echo "$TRANSCRIPTIONS" | grep -c "." || echo "0")

if [[ "$FILE_COUNT" -eq 0 ]]; then
    echo "Error: No transcription files found"
    exit 1
fi

echo "Found $FILE_COUNT file(s)"

> "$OUTPUT_FILE"
MERGED=0
WORDS=0

for file in $TRANSCRIPTIONS; do
    filename=$(basename "$file")

    if grep -q "^ERROR:" "$file" 2>/dev/null || [[ ! -s "$file" ]]; then
        echo "[SKIP] $filename"
        continue
    fi

    echo "[MERGE] $filename"

    if [[ "$file" == *.json ]] && command -v jq &>/dev/null; then
        content=$(jq -r '.text // empty' "$file" 2>/dev/null || cat "$file")
    else
        content=$(cat "$file")
    fi

    WORDS=$((WORDS + $(echo "$content" | wc -w)))

    [[ "$ADD_MARKERS" == "true" ]] && echo -e "\n--- [$filename] ---\n" >> "$OUTPUT_FILE"
    [[ $MERGED -gt 0 ]] && echo "" >> "$OUTPUT_FILE"
    echo "$content" >> "$OUTPUT_FILE"
    MERGED=$((MERGED + 1))
done

echo ""
echo "=========================================="
echo "Complete! Merged $MERGED files (~$WORDS words)"
echo "Output: $OUTPUT_FILE"
