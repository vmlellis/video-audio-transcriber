#!/usr/bin/env bash
#
# compress_audio.sh
# =================
# Compresses and normalizes audio for optimal transcription.
#
# Usage:
#   ./compress_audio.sh <input_audio> <output_audio>
#
# Environment variables:
#   AUDIO_BITRATE     - Output bitrate (default: 64k)
#   AUDIO_NORMALIZE   - Enable loudness normalization (default: true)
#
# Example:
#   AUDIO_BITRATE=48k ./compress_audio.sh input.wav output.mp3
#
# Why compress?
#   - OpenAI API has a 25MB file size limit
#   - Lower bitrate = smaller files = lower API transfer time
#   - 64kbps is sufficient for speech (voice doesn't need high fidelity)
#   - Normalization ensures consistent volume levels
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Output bitrate
# 64k is a good balance for speech (clear audio, small files)
# 48k works fine for most speech but may lose some clarity
# 32k is very compressed but still usable for transcription
AUDIO_BITRATE="${AUDIO_BITRATE:-64k}"

# Sample rate (16kHz is optimal for Whisper API)
SAMPLE_RATE="${SAMPLE_RATE:-16000}"

# Number of channels (mono for transcription)
CHANNELS="${CHANNELS:-1}"

# Enable loudness normalization
AUDIO_NORMALIZE="${AUDIO_NORMALIZE:-true}"

# ------------------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input_audio> <output_audio>"
    echo ""
    echo "Arguments:"
    echo "  input_audio   Path to the input audio file"
    echo "  output_audio  Path for the compressed output (should be .mp3)"
    echo ""
    echo "Environment variables:"
    echo "  AUDIO_BITRATE   Output bitrate (default: 64k)"
    echo "  AUDIO_NORMALIZE Enable normalization (default: true)"
    echo ""
    echo "Example:"
    echo "  AUDIO_BITRATE=48k $0 input.wav output.mp3"
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
echo "Compressing audio"
echo "=========================================="
echo "Input:  $INPUT_AUDIO"
echo "Output: $OUTPUT_AUDIO"
echo ""
echo "Compression settings:"
echo "  Bitrate: $AUDIO_BITRATE"
echo "  Sample rate: $SAMPLE_RATE Hz"
echo "  Channels: $CHANNELS (mono)"
echo "  Normalize: $AUDIO_NORMALIZE"
echo ""

INPUT_SIZE=$(du -h "$INPUT_AUDIO" | cut -f1)
echo "Input file size: $INPUT_SIZE"
echo ""

# ------------------------------------------------------------------------------
# Build ffmpeg filter chain
# ------------------------------------------------------------------------------

# Start with empty filter
FILTER_CHAIN=""

# Add loudness normalization if enabled
# loudnorm filter normalizes audio to broadcast standards
# This ensures consistent volume across different recordings
if [[ "$AUDIO_NORMALIZE" == "true" ]]; then
    # loudnorm parameters:
    #   I=-16    : Integrated loudness target (-16 LUFS is broadcast standard)
    #   TP=-1.5  : True peak max (-1.5 dB prevents clipping)
    #   LRA=11   : Loudness range (dynamic range target)
    FILTER_CHAIN="loudnorm=I=-16:TP=-1.5:LRA=11"
    echo "Applying loudness normalization (target: -16 LUFS)..."
fi

# ------------------------------------------------------------------------------
# Compress audio
# ------------------------------------------------------------------------------

echo "Compressing audio..."

# Determine output format
OUTPUT_EXT="${OUTPUT_AUDIO##*.}"

if [[ -n "$FILTER_CHAIN" ]]; then
    FILTER_ARG="-af $FILTER_CHAIN"
else
    FILTER_ARG=""
fi

case "$OUTPUT_EXT" in
    mp3)
        # MP3 compression with libmp3lame
        ffmpeg -y -i "$INPUT_AUDIO" \
            $FILTER_ARG \
            -ar "$SAMPLE_RATE" \
            -ac "$CHANNELS" \
            -acodec libmp3lame \
            -b:a "$AUDIO_BITRATE" \
            "$OUTPUT_AUDIO" 2>&1 | grep -E "^(size=|time=)" || true
        ;;
    m4a|aac)
        # AAC compression (slightly better quality than MP3 at same bitrate)
        ffmpeg -y -i "$INPUT_AUDIO" \
            $FILTER_ARG \
            -ar "$SAMPLE_RATE" \
            -ac "$CHANNELS" \
            -acodec aac \
            -b:a "$AUDIO_BITRATE" \
            "$OUTPUT_AUDIO" 2>&1 | grep -E "^(size=|time=)" || true
        ;;
    *)
        echo "Warning: Unknown format '.$OUTPUT_EXT', using MP3"
        ffmpeg -y -i "$INPUT_AUDIO" \
            $FILTER_ARG \
            -ar "$SAMPLE_RATE" \
            -ac "$CHANNELS" \
            -acodec libmp3lame \
            -b:a "$AUDIO_BITRATE" \
            "${OUTPUT_AUDIO%.*}.mp3" 2>&1 | grep -E "^(size=|time=)" || true
        OUTPUT_AUDIO="${OUTPUT_AUDIO%.*}.mp3"
        ;;
esac

# ------------------------------------------------------------------------------
# Verify output and show statistics
# ------------------------------------------------------------------------------

if [[ -f "$OUTPUT_AUDIO" ]]; then
    OUTPUT_SIZE=$(du -h "$OUTPUT_AUDIO" | cut -f1)
    OUTPUT_SIZE_BYTES=$(stat -f%z "$OUTPUT_AUDIO" 2>/dev/null || stat -c%s "$OUTPUT_AUDIO" 2>/dev/null || echo "0")
    DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_AUDIO" 2>/dev/null || echo "unknown")

    # Check if file is under 25MB API limit
    MAX_SIZE_BYTES=26214400  # 25MB in bytes
    if [[ "$OUTPUT_SIZE_BYTES" -gt "$MAX_SIZE_BYTES" ]]; then
        echo ""
        echo "⚠️  Warning: Output file exceeds 25MB API limit!"
        echo "   Consider using lower bitrate or smaller chunks."
    fi

    echo ""
    echo "=========================================="
    echo "Compression complete!"
    echo "=========================================="
    echo "Output file: $OUTPUT_AUDIO"
    echo "File size: $OUTPUT_SIZE"
    echo "Duration: ${DURATION}s"
    echo "Bitrate: $AUDIO_BITRATE"
else
    echo "Error: Failed to create output file"
    exit 1
fi
