#!/usr/bin/env bash
#
# remove_silence.sh
# =================
# Removes long silences from an audio file.
#
# Usage:
#   ./remove_silence.sh <input_audio> <output_audio>
#
# Environment variables:
#   SILENCE_THRESHOLD  - Volume threshold for silence detection (default: 0.03)
#                        Range: 0.0 to 1.0 (0 = absolute silence, 1 = max volume)
#   SILENCE_DURATION   - Minimum silence duration to remove in seconds (default: 2.0)
#
# Example:
#   SILENCE_DURATION=3.0 ./remove_silence.sh input.wav output.wav
#
# How it works:
#   This script uses ffmpeg's silenceremove filter to detect and remove
#   silent portions of the audio. The filter works in two passes:
#   1. First pass: Remove silence from the beginning
#   2. Second pass: Remove silence from throughout the file
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Silence threshold (0 to 1)
# Lower values = more aggressive silence detection
# 0.03 works well for speech with minimal background noise
SILENCE_THRESHOLD="${SILENCE_THRESHOLD:-0.03}"

# Minimum silence duration to remove (in seconds)
# Silences shorter than this will be kept (natural pauses)
SILENCE_DURATION="${SILENCE_DURATION:-2.0}"

# Keep a small amount of silence at transitions (in seconds)
# This prevents words from being cut off
SILENCE_KEEP="${SILENCE_KEEP:-0.3}"

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
    echo "  SILENCE_THRESHOLD  Volume threshold (0-1, default: 0.03)"
    echo "  SILENCE_DURATION   Min silence to remove in seconds (default: 2.0)"
    echo ""
    echo "Example:"
    echo "  SILENCE_DURATION=3.0 $0 input.wav output.wav"
    exit 1
fi

INPUT_AUDIO="$1"
OUTPUT_AUDIO="$2"

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

# Create output directory if it doesn't exist
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
echo "Silence detection settings:"
echo "  Threshold: $SILENCE_THRESHOLD (volume level)"
echo "  Min duration: ${SILENCE_DURATION}s"
echo "  Keep padding: ${SILENCE_KEEP}s"
echo ""

# Get original duration
ORIGINAL_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_AUDIO" 2>/dev/null || echo "0")
echo "Original duration: ${ORIGINAL_DURATION}s"
echo ""

# ------------------------------------------------------------------------------
# Remove silence using ffmpeg silenceremove filter
# ------------------------------------------------------------------------------

# Filter explanation:
# silenceremove=
#   stop_periods=-1        : Remove silence throughout the file (not just start)
#   stop_duration=X        : Minimum silence duration to be removed
#   stop_threshold=X       : Volume threshold below which is considered silence
#   stop_silence=X         : Keep X seconds of silence at each transition
#   detection=peak         : Use peak detection (alternative: rms)

echo "Processing audio..."

ffmpeg -y -i "$INPUT_AUDIO" \
    -af "silenceremove=stop_periods=-1:stop_duration=${SILENCE_DURATION}:stop_threshold=${SILENCE_THRESHOLD}:stop_silence=${SILENCE_KEEP}:detection=peak" \
    -acodec pcm_s16le \
    "$OUTPUT_AUDIO" 2>&1 | grep -E "^(size=|time=)" || true

# ------------------------------------------------------------------------------
# Verify output and show statistics
# ------------------------------------------------------------------------------

if [[ -f "$OUTPUT_AUDIO" ]]; then
    NEW_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_AUDIO" 2>/dev/null || echo "0")

    # Calculate time saved
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
    echo "Error: Failed to create output file"
    exit 1
fi
