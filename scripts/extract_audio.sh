#!/usr/bin/env bash
#
# extract_audio.sh
# ================
# Extracts audio from a video file.
#
# Usage:
#   ./extract_audio.sh <input_video> <output_audio>
#
# Example:
#   ./extract_audio.sh input/video.mp4 output/audio_raw.wav
#
# Output formats supported:
#   - .wav (recommended for processing, lossless)
#   - .mp3 (smaller file size)
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Audio sample rate (Hz) - 16000 is optimal for speech recognition
SAMPLE_RATE="${SAMPLE_RATE:-16000}"

# Number of audio channels (1 = mono, recommended for transcription)
CHANNELS="${CHANNELS:-1}"

# ------------------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input_video> <output_audio>"
    echo ""
    echo "Arguments:"
    echo "  input_video   Path to the input video file"
    echo "  output_audio  Path for the output audio file (.wav or .mp3)"
    echo ""
    echo "Example:"
    echo "  $0 input/lecture.mp4 output/audio_raw.wav"
    exit 1
fi

INPUT_VIDEO="$1"
OUTPUT_AUDIO="$2"

# Check if input file exists
if [[ ! -f "$INPUT_VIDEO" ]]; then
    echo "Error: Input file not found: $INPUT_VIDEO"
    exit 1
fi

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed. Please install it first."
    echo "  Ubuntu/Debian: sudo apt install ffmpeg"
    echo "  macOS: brew install ffmpeg"
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_AUDIO")
mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# Extract audio
# ------------------------------------------------------------------------------

echo "=========================================="
echo "Extracting audio from video"
echo "=========================================="
echo "Input:  $INPUT_VIDEO"
echo "Output: $OUTPUT_AUDIO"
echo "Sample rate: $SAMPLE_RATE Hz"
echo "Channels: $CHANNELS (mono)"
echo ""

# Get input file information
echo "Input file info:"
ffprobe -v quiet -show_format -show_streams "$INPUT_VIDEO" 2>/dev/null | grep -E "^(duration|bit_rate|codec_name|sample_rate)=" | head -10 || true
echo ""

# Determine output format based on file extension
OUTPUT_EXT="${OUTPUT_AUDIO##*.}"

case "$OUTPUT_EXT" in
    wav)
        # WAV output - PCM signed 16-bit little-endian
        # Best quality for processing, larger file size
        echo "Extracting to WAV format (lossless)..."
        ffmpeg -y -i "$INPUT_VIDEO" \
            -vn \
            -acodec pcm_s16le \
            -ar "$SAMPLE_RATE" \
            -ac "$CHANNELS" \
            "$OUTPUT_AUDIO"
        ;;
    mp3)
        # MP3 output - Good compression, slight quality loss
        echo "Extracting to MP3 format (compressed)..."
        ffmpeg -y -i "$INPUT_VIDEO" \
            -vn \
            -acodec libmp3lame \
            -ar "$SAMPLE_RATE" \
            -ac "$CHANNELS" \
            -q:a 2 \
            "$OUTPUT_AUDIO"
        ;;
    *)
        echo "Warning: Unknown output format '.$OUTPUT_EXT', defaulting to WAV settings"
        ffmpeg -y -i "$INPUT_VIDEO" \
            -vn \
            -ar "$SAMPLE_RATE" \
            -ac "$CHANNELS" \
            "$OUTPUT_AUDIO"
        ;;
esac

# ------------------------------------------------------------------------------
# Verify output
# ------------------------------------------------------------------------------

if [[ -f "$OUTPUT_AUDIO" ]]; then
    OUTPUT_SIZE=$(du -h "$OUTPUT_AUDIO" | cut -f1)
    OUTPUT_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_AUDIO" 2>/dev/null || echo "unknown")

    echo ""
    echo "=========================================="
    echo "Audio extraction complete!"
    echo "=========================================="
    echo "Output file: $OUTPUT_AUDIO"
    echo "File size: $OUTPUT_SIZE"
    echo "Duration: ${OUTPUT_DURATION}s"
else
    echo "Error: Failed to create output file"
    exit 1
fi
