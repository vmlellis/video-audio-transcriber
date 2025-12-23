#!/usr/bin/env bash
#
# remove_silence.sh
# =================
# Removes long silences from an audio file using smart silence detection.
#
# Usage:
#   ./remove_silence.sh <input_audio> <output_audio>
#
# Environment variables:
#   SILENCE_THRESHOLD  - Volume threshold for silence detection (default: 0.02)
#   SILENCE_DURATION   - Minimum silence duration to remove in seconds (default: 2.0)
#   SILENCE_KEEP       - Amount of silence to keep at transitions (default: 0.8)
#
# Example:
#   SILENCE_DURATION=3.0 ./remove_silence.sh input.wav output.wav
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Silence threshold (0 to 1)
# Lower values = more aggressive silence detection
SILENCE_THRESHOLD="${SILENCE_THRESHOLD:-0.02}"

# Minimum silence duration to remove (in seconds)
SILENCE_DURATION="${SILENCE_DURATION:-2.0}"

# Keep silence at transitions (in seconds) - higher = smoother but less compression
SILENCE_KEEP="${SILENCE_KEEP:-0.8}"

# ------------------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input_audio> <output_audio>"
    echo ""
    echo "Arguments:"
    echo "  input_audio   Path to the input audio file"
    echo "  output_audio  Path for the output audio file (silence removed)"
    echo ""
    echo "Environment variables:"
    echo "  SILENCE_THRESHOLD  Volume threshold (0-1, default: 0.02)"
    echo "  SILENCE_DURATION   Min silence to remove in seconds (default: 2.0)"
    echo "  SILENCE_KEEP       Silence to keep at transitions (default: 0.8)"
    echo ""
    echo "Example:"
    echo "  SILENCE_DURATION=3.0 $0 input.wav output.wav"
    exit 1
fi

INPUT_AUDIO="$1"
OUTPUT_AUDIO="$2"

if [[ ! -f "$INPUT_AUDIO" ]]; then
    echo "Error: Input file not found: $INPUT_AUDIO"
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed."
    exit 1
fi

OUTPUT_DIR=$(dirname "$OUTPUT_AUDIO")
mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# Get input file info
# ------------------------------------------------------------------------------

echo "=========================================="
echo "Removing silence from audio"
echo "=========================================="
echo "Input:  $INPUT_AUDIO"
echo "Output: $OUTPUT_AUDIO"
echo ""
echo "Settings:"
echo "  Threshold: $SILENCE_THRESHOLD"
echo "  Min duration: ${SILENCE_DURATION}s"
echo "  Keep padding: ${SILENCE_KEEP}s"
echo ""

ORIGINAL_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_AUDIO" 2>/dev/null || echo "0")
echo "Original duration: ${ORIGINAL_DURATION}s"
echo ""

# ------------------------------------------------------------------------------
# Remove silence using silenceremove filter with RMS detection
# ------------------------------------------------------------------------------

# Using RMS detection instead of peak for smoother results
# window parameter helps prevent abrupt cuts
#
# Filter chain:
# 1. silenceremove - removes long silences, keeping padding at transitions
# 2. aresample=async=1 - smooths any small discontinuities in the waveform
# 3. highpass=f=20 - removes DC offset and sub-bass rumble that can cause clicks

echo "Processing audio..."

FILTER="silenceremove=stop_periods=-1:stop_duration=${SILENCE_DURATION}:stop_threshold=${SILENCE_THRESHOLD}:stop_silence=${SILENCE_KEEP}:detection=rms:window=0.1"
FILTER="$FILTER,aresample=async=1:first_pts=0"
FILTER="$FILTER,highpass=f=20"

ffmpeg -y -i "$INPUT_AUDIO" \
    -af "$FILTER" \
    -acodec pcm_s16le \
    "$OUTPUT_AUDIO" 2>&1 | tail -5

# ------------------------------------------------------------------------------
# Verify output and show statistics
# ------------------------------------------------------------------------------

if [[ -f "$OUTPUT_AUDIO" ]] && [[ $(stat -c%s "$OUTPUT_AUDIO" 2>/dev/null || stat -f%z "$OUTPUT_AUDIO" 2>/dev/null) -gt 1000 ]]; then
    NEW_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_AUDIO" 2>/dev/null || echo "0")

    if [[ "$ORIGINAL_DURATION" != "0" && "$NEW_DURATION" != "0" ]]; then
        TIME_SAVED=$(echo "$ORIGINAL_DURATION - $NEW_DURATION" | bc 2>/dev/null || echo "N/A")
        PERCENT_SAVED=$(echo "scale=1; ($ORIGINAL_DURATION - $NEW_DURATION) / $ORIGINAL_DURATION * 100" | bc 2>/dev/null || echo "N/A")
    else
        TIME_SAVED="N/A"
        PERCENT_SAVED="N/A"
    fi

    OUTPUT_SIZE=$(du -h "$OUTPUT_AUDIO" | cut -f1)

    echo ""
    echo "=========================================="
    echo "Silence removal complete!"
    echo "=========================================="
    echo "Output file: $OUTPUT_AUDIO"
    echo "File size: $OUTPUT_SIZE"
    echo ""
    echo "Duration comparison:"
    echo "  Original:  ${ORIGINAL_DURATION}s"
    echo "  Processed: ${NEW_DURATION}s"
    echo "  Removed:   ${TIME_SAVED}s (${PERCENT_SAVED}%)"
else
    echo "Error: Failed to create output file or file is too small"
    exit 1
fi
