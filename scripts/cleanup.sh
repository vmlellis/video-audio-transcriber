#!/usr/bin/env bash
#
# cleanup.sh - Remove intermediate files, keeping only final transcription
#
# Usage: ./cleanup.sh [output_directory]
#

set -euo pipefail

OUTPUT_DIR="${1:-output}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Error: Directory not found: $OUTPUT_DIR"
    exit 1
fi

echo "Cleaning up intermediate files in: $OUTPUT_DIR"

# Check if final transcription exists
if [[ ! -f "$OUTPUT_DIR/final_transcription.txt" ]]; then
    echo "Warning: final_transcription.txt not found. Aborting cleanup."
    exit 1
fi

# Remove intermediate audio files
rm -f "$OUTPUT_DIR/audio_raw.wav"
rm -f "$OUTPUT_DIR/audio_trimmed.wav"
rm -f "$OUTPUT_DIR/audio_compressed.mp3"

# Remove chunks directory
rm -rf "$OUTPUT_DIR/chunks"

# Remove individual transcriptions (keep only merged)
rm -rf "$OUTPUT_DIR/transcriptions"

echo "Cleanup complete!"
echo "Kept: $OUTPUT_DIR/final_transcription.txt"
