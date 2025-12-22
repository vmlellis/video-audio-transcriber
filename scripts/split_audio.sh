#!/usr/bin/env bash
#
# split_audio.sh
# ==============
# Splits audio into chunks at natural silence points (smart splitting).
#
# This script avoids cutting in the middle of speech by:
# 1. Detecting silence points in the audio using ffmpeg
# 2. Finding silences near the target chunk duration
# 3. Cutting at those natural pause points
#
# Usage:
#   ./split_audio.sh <input_audio> <output_directory>
#
# Environment variables:
#   CHUNK_DURATION      - Target duration per chunk in seconds (default: 1800 = 30min)
#   CHUNK_TOLERANCE     - How far from target to look for silence (default: 120 = 2min)
#   SILENCE_THRESHOLD   - Volume threshold for silence detection (default: -40dB)
#   SILENCE_MIN_LEN     - Minimum silence length to consider (default: 0.5s)
#
# Example:
#   CHUNK_DURATION=900 ./split_audio.sh input.mp3 output/chunks/
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Target chunk duration in seconds (default: 30 minutes)
CHUNK_DURATION="${CHUNK_DURATION:-1800}"

# Tolerance: how far before/after target to look for silence (default: 2 minutes)
CHUNK_TOLERANCE="${CHUNK_TOLERANCE:-120}"

# Silence detection threshold in dB (more negative = quieter sounds count as silence)
SILENCE_THRESHOLD="${SILENCE_THRESHOLD:--40}"

# Minimum silence duration to consider as a valid cut point (seconds)
SILENCE_MIN_LEN="${SILENCE_MIN_LEN:-0.5}"

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
    echo "  CHUNK_DURATION    Target duration per chunk (default: 1800 = 30min)"
    echo "  CHUNK_TOLERANCE   Search range for silence (default: 120 = 2min)"
    echo "  SILENCE_THRESHOLD Detection threshold in dB (default: -40)"
    echo ""
    echo "Example:"
    echo "  CHUNK_DURATION=900 $0 input.mp3 output/chunks/"
    exit 1
fi

INPUT_AUDIO="$1"
OUTPUT_DIR="$2"

if [[ ! -f "$INPUT_AUDIO" ]]; then
    echo "Error: Input file not found: $INPUT_AUDIO"
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# Get input file info
# ------------------------------------------------------------------------------

echo "=========================================="
echo "Smart Audio Splitting"
echo "=========================================="
echo "Input:  $INPUT_AUDIO"
echo "Output: $OUTPUT_DIR"
echo ""
echo "Settings:"
echo "  Target chunk duration: ${CHUNK_DURATION}s ($(echo "scale=1; $CHUNK_DURATION / 60" | bc)min)"
echo "  Tolerance window: ±${CHUNK_TOLERANCE}s"
echo "  Silence threshold: ${SILENCE_THRESHOLD}dB"
echo ""

TOTAL_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_AUDIO" 2>/dev/null || echo "0")
TOTAL_DURATION_INT=${TOTAL_DURATION%.*}

echo "Total duration: ${TOTAL_DURATION}s"
echo ""

INPUT_EXT="${INPUT_AUDIO##*.}"

# ------------------------------------------------------------------------------
# Detect all silence points
# ------------------------------------------------------------------------------

echo "Detecting silence points..."

SILENCE_FILE=$(mktemp)
trap "rm -f $SILENCE_FILE" EXIT

# Use silencedetect filter to find all silence points
# Output format: silence_end: 123.456 | silence_duration: 0.789
ffmpeg -i "$INPUT_AUDIO" -af "silencedetect=noise=${SILENCE_THRESHOLD}dB:d=${SILENCE_MIN_LEN}" -f null - 2>&1 | \
    grep "silence_end" | \
    sed -E 's/.*silence_end: ([0-9.]+).*/\1/' > "$SILENCE_FILE" || true

SILENCE_COUNT=$(wc -l < "$SILENCE_FILE" | tr -d ' ')
echo "Found $SILENCE_COUNT silence points"
echo ""

# ------------------------------------------------------------------------------
# Find optimal cut points
# ------------------------------------------------------------------------------

find_best_silence() {
    local target=$1
    local min_time=$((target - CHUNK_TOLERANCE))
    local max_time=$((target + CHUNK_TOLERANCE))
    local best_silence=""
    local best_diff=999999

    while read -r silence_time; do
        silence_int=${silence_time%.*}
        if [[ $silence_int -ge $min_time && $silence_int -le $max_time ]]; then
            diff=$((silence_int - target))
            [[ $diff -lt 0 ]] && diff=$((-diff))
            if [[ $diff -lt $best_diff ]]; then
                best_diff=$diff
                best_silence=$silence_time
            fi
        fi
    done < "$SILENCE_FILE"

    echo "$best_silence"
}

# ------------------------------------------------------------------------------
# Split audio at optimal points
# ------------------------------------------------------------------------------

echo "Splitting audio at natural pause points..."
echo ""

CUT_POINTS=()
current_pos=0
target_pos=$CHUNK_DURATION
chunk_num=1

while [[ $target_pos -lt $TOTAL_DURATION_INT ]]; do
    # Find best silence near target
    best_cut=$(find_best_silence $target_pos)

    if [[ -n "$best_cut" ]]; then
        echo "  Chunk $chunk_num: Cut at ${best_cut}s (target was ${target_pos}s, found silence)"
        CUT_POINTS+=("$best_cut")
    else
        echo "  Chunk $chunk_num: Cut at ${target_pos}s (no silence found, using exact time)"
        CUT_POINTS+=("$target_pos")
    fi

    # Move to next target
    last_cut=${CUT_POINTS[-1]%.*}
    target_pos=$((last_cut + CHUNK_DURATION))
    chunk_num=$((chunk_num + 1))
done

echo ""
echo "Creating ${#CUT_POINTS[@]} chunks..."

# ------------------------------------------------------------------------------
# Extract chunks using cut points
# ------------------------------------------------------------------------------

start_time=0
chunk_idx=1

for cut_point in "${CUT_POINTS[@]}"; do
    output_file=$(printf "${OUTPUT_DIR}/chunk_%03d.${INPUT_EXT}" $chunk_idx)
    duration=$(echo "$cut_point - $start_time" | bc)

    ffmpeg -y -i "$INPUT_AUDIO" \
        -ss "$start_time" \
        -t "$duration" \
        -c copy \
        "$output_file" 2>/dev/null

    start_time=$cut_point
    chunk_idx=$((chunk_idx + 1))
done

# Extract final chunk (from last cut point to end)
output_file=$(printf "${OUTPUT_DIR}/chunk_%03d.${INPUT_EXT}" $chunk_idx)
ffmpeg -y -i "$INPUT_AUDIO" \
    -ss "$start_time" \
    -c copy \
    "$output_file" 2>/dev/null

# ------------------------------------------------------------------------------
# Verify output
# ------------------------------------------------------------------------------

CREATED_CHUNKS=$(find "$OUTPUT_DIR" -name "chunk_*.${INPUT_EXT}" -type f | wc -l | tr -d ' ')

if [[ "$CREATED_CHUNKS" -gt 0 ]]; then
    echo ""
    echo "=========================================="
    echo "Smart splitting complete!"
    echo "=========================================="
    echo "Output directory: $OUTPUT_DIR"
    echo "Chunks created: $CREATED_CHUNKS"
    echo ""
    echo "Chunk details:"

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
