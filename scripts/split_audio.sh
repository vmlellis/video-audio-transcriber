#!/usr/bin/env bash
#
# split_audio.sh
# ==============
# Splits an audio file into chunks of a specified duration.
#
# Usage:
#   ./split_audio.sh <input_audio> <output_directory>
#
# Environment variables:
#   CHUNK_DURATION  - Duration of each chunk in seconds (default: 1800 = 30 minutes)
#
# Example:
#   CHUNK_DURATION=900 ./split_audio.sh input.mp3 output/chunks/
#
# Output:
#   Creates files named chunk_001.mp3, chunk_002.mp3, etc.
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Chunk duration in seconds (default: 30 minutes)
CHUNK_DURATION="${CHUNK_DURATION:-1800}"

# ------------------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input_audio> <output_directory>"
    echo ""
    echo "Arguments:"
    echo "  input_audio       Path to the input audio file"
    echo "  output_directory  Directory to store audio chunks"
    echo ""
    echo "Environment variables:"
    echo "  CHUNK_DURATION  Duration per chunk in seconds (default: 1800 = 30min)"
    echo ""
    echo "Example:"
    echo "  CHUNK_DURATION=900 $0 input.mp3 output/chunks/"
    exit 1
fi

INPUT_AUDIO="$1"
OUTPUT_DIR="$2"

# Check if input file exists
if [[ ! -f "$INPUT_AUDIO" ]]; then
    echo "Error: Input file not found: $INPUT_AUDIO"
    exit 1
fi

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# Get input file info
# ------------------------------------------------------------------------------

echo "=========================================="
echo "Splitting audio into chunks"
echo "=========================================="
echo "Input:  $INPUT_AUDIO"
echo "Output: $OUTPUT_DIR"
echo ""
echo "Chunk settings:"
echo "  Duration: ${CHUNK_DURATION}s ($(echo "scale=1; $CHUNK_DURATION / 60" | bc) minutes)"
echo ""

# Get audio duration
TOTAL_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_AUDIO" 2>/dev/null || echo "0")
TOTAL_DURATION_INT=${TOTAL_DURATION%.*}

# Calculate expected number of chunks
NUM_CHUNKS=$(( (TOTAL_DURATION_INT + CHUNK_DURATION - 1) / CHUNK_DURATION ))

echo "Total duration: ${TOTAL_DURATION}s"
echo "Expected chunks: $NUM_CHUNKS"
echo ""

# Get input file extension
INPUT_EXT="${INPUT_AUDIO##*.}"

# ------------------------------------------------------------------------------
# Split audio using ffmpeg segment
# ------------------------------------------------------------------------------

echo "Splitting audio..."
echo ""

# Use segment muxer to split audio
# -f segment          : Use segment output format
# -segment_time       : Duration of each segment
# -reset_timestamps 1 : Reset timestamps for each segment (important for API)
# -c copy             : Copy codec without re-encoding (fast)

ffmpeg -y -i "$INPUT_AUDIO" \
    -f segment \
    -segment_time "$CHUNK_DURATION" \
    -reset_timestamps 1 \
    -c copy \
    "${OUTPUT_DIR}/chunk_%03d.${INPUT_EXT}" 2>&1 | grep -E "^(Opening|segment)" || true

# ------------------------------------------------------------------------------
# Verify output and show statistics
# ------------------------------------------------------------------------------

# Count created chunks
CREATED_CHUNKS=$(find "$OUTPUT_DIR" -name "chunk_*.${INPUT_EXT}" -type f | wc -l | tr -d ' ')

if [[ "$CREATED_CHUNKS" -gt 0 ]]; then
    echo ""
    echo "=========================================="
    echo "Splitting complete!"
    echo "=========================================="
    echo "Output directory: $OUTPUT_DIR"
    echo "Chunks created: $CREATED_CHUNKS"
    echo ""
    echo "Chunk details:"

    # List all chunks with their sizes and durations
    CHUNK_NUM=1
    for chunk in $(find "$OUTPUT_DIR" -name "chunk_*.${INPUT_EXT}" -type f | sort); do
        CHUNK_SIZE=$(du -h "$chunk" | cut -f1)
        CHUNK_DUR=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$chunk" 2>/dev/null || echo "?")
        CHUNK_DUR_FORMATTED=$(printf "%.1f" "$CHUNK_DUR" 2>/dev/null || echo "$CHUNK_DUR")
        echo "  [$CHUNK_NUM] $(basename "$chunk") - ${CHUNK_SIZE} (${CHUNK_DUR_FORMATTED}s)"
        CHUNK_NUM=$((CHUNK_NUM + 1))
    done
else
    echo "Error: No chunks were created"
    exit 1
fi
