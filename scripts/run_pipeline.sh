#!/usr/bin/env bash
#
# run_pipeline.sh - Orchestrates the full transcription pipeline
#
# Usage: ./run_pipeline.sh <input_video>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration with defaults
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/output}"
SILENCE_THRESHOLD="${SILENCE_THRESHOLD:-0.03}"
SILENCE_DURATION="${SILENCE_DURATION:-2.0}"
CHUNK_DURATION="${CHUNK_DURATION:-1800}"
AUDIO_BITRATE="${AUDIO_BITRATE:-64k}"
PARALLEL_JOBS="${PARALLEL_JOBS:-2}"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input_video>"
    echo ""
    echo "Example: $0 input/lecture.mp4"
    echo ""
    echo "Environment variables:"
    echo "  OPENAI_API_KEY     (required) Your OpenAI API key"
    echo "  OUTPUT_DIR         Output directory (default: ./output)"
    echo "  SILENCE_DURATION   Min silence to remove (default: 2.0s)"
    echo "  CHUNK_DURATION     Chunk length in seconds (default: 1800)"
    echo "  PARALLEL_JOBS      Parallel transcriptions (default: 2)"
    echo "  CLEANUP            Remove intermediate files when done (default: false)"
    exit 1
fi

INPUT_VIDEO="$1"

if [[ ! -f "$INPUT_VIDEO" ]]; then
    echo "Error: Input file not found: $INPUT_VIDEO"
    exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "Error: OPENAI_API_KEY is not set"
    exit 1
fi

# Create output directories
mkdir -p "$OUTPUT_DIR/chunks" "$OUTPUT_DIR/transcriptions"

VIDEO_NAME=$(basename "$INPUT_VIDEO" | sed 's/\.[^.]*$//')

echo "=========================================="
echo "Video Audio Transcriber Pipeline"
echo "=========================================="
echo "Input: $INPUT_VIDEO"
echo "Output: $OUTPUT_DIR"
echo ""

# Step 1: Extract audio
echo "[1/6] Extracting audio..."
"$SCRIPT_DIR/extract_audio.sh" "$INPUT_VIDEO" "$OUTPUT_DIR/audio_raw.wav"
echo ""

# Step 2: Remove silence
echo "[2/6] Removing silence..."
"$SCRIPT_DIR/remove_silence.sh" "$OUTPUT_DIR/audio_raw.wav" "$OUTPUT_DIR/audio_trimmed.wav"
echo ""

# Step 3: Compress audio
echo "[3/6] Compressing audio..."
"$SCRIPT_DIR/compress_audio.sh" "$OUTPUT_DIR/audio_trimmed.wav" "$OUTPUT_DIR/audio_compressed.mp3"
echo ""

# Step 4: Split into chunks
echo "[4/6] Splitting into chunks..."
"$SCRIPT_DIR/split_audio.sh" "$OUTPUT_DIR/audio_compressed.mp3" "$OUTPUT_DIR/chunks/"
echo ""

# Step 5: Transcribe chunks
echo "[5/6] Transcribing chunks..."
"$SCRIPT_DIR/transcribe_chunks.sh" "$OUTPUT_DIR/chunks/" "$OUTPUT_DIR/transcriptions/"
echo ""

# Step 6: Merge transcriptions
echo "[6/6] Merging transcriptions..."
"$SCRIPT_DIR/merge_transcriptions.sh" "$OUTPUT_DIR/transcriptions/" "$OUTPUT_DIR/final_transcription.txt"
echo ""

echo "=========================================="
echo "Pipeline complete!"
echo "=========================================="
echo ""
echo "Final transcription: $OUTPUT_DIR/final_transcription.txt"

# Optional cleanup
if [[ "${CLEANUP:-false}" == "true" ]]; then
    echo ""
    "$SCRIPT_DIR/cleanup.sh" "$OUTPUT_DIR"
fi
