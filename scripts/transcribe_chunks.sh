#!/usr/bin/env bash
#
# transcribe_chunks.sh
# ====================
# Transcribes audio chunks using OpenAI's Whisper API.
#
# Usage:
#   ./transcribe_chunks.sh <chunks_directory> <output_directory>
#
# Environment variables (required):
#   OPENAI_API_KEY    - Your OpenAI API key
#
# Environment variables (optional):
#   PARALLEL_JOBS     - Number of parallel transcription jobs (default: 2)
#   WHISPER_MODEL     - Whisper model to use (default: whisper-1)
#   RESPONSE_FORMAT   - Output format: json, text, srt, vtt (default: text)
#   LANGUAGE          - Language code for transcription (default: auto-detect)
#
# Example:
#   PARALLEL_JOBS=4 ./transcribe_chunks.sh output/chunks/ output/transcriptions/
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# OpenAI API endpoint for transcription
API_ENDPOINT="https://api.openai.com/v1/audio/transcriptions"

# Number of parallel jobs (be careful with rate limits)
PARALLEL_JOBS="${PARALLEL_JOBS:-2}"

# Whisper model
WHISPER_MODEL="${WHISPER_MODEL:-whisper-1}"

# Response format (text, json, srt, verbose_json, vtt)
RESPONSE_FORMAT="${RESPONSE_FORMAT:-text}"

# Language (empty = auto-detect)
LANGUAGE="${LANGUAGE:-}"

# Retry settings
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# ------------------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <chunks_directory> <output_directory>"
    echo ""
    echo "Arguments:"
    echo "  chunks_directory  Directory containing audio chunks"
    echo "  output_directory  Directory to store transcriptions"
    echo ""
    echo "Environment variables:"
    echo "  OPENAI_API_KEY   (required) Your OpenAI API key"
    echo "  PARALLEL_JOBS    Number of parallel jobs (default: 2)"
    echo "  WHISPER_MODEL    Model to use (default: whisper-1)"
    echo "  RESPONSE_FORMAT  Output format (default: text)"
    echo "  LANGUAGE         Language code (default: auto-detect)"
    echo ""
    echo "Example:"
    echo "  export OPENAI_API_KEY='sk-...'"
    echo "  $0 output/chunks/ output/transcriptions/"
    exit 1
fi

CHUNKS_DIR="$1"
OUTPUT_DIR="$2"

# Check if API key is set
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "Error: OPENAI_API_KEY environment variable is not set."
    echo "Please set it with: export OPENAI_API_KEY='sk-your-key-here'"
    exit 1
fi

# Check if chunks directory exists
if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "Error: Chunks directory not found: $CHUNKS_DIR"
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed."
    exit 1
fi

# Check if jq is available (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it for JSON processing."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# Transcription function
# ------------------------------------------------------------------------------

transcribe_file() {
    local input_file="$1"
    local output_file="$2"
    local filename=$(basename "$input_file")

    echo "[$(date '+%H:%M:%S')] Transcribing: $filename"

    # Check file size (API limit is 25MB)
    local file_size=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file" 2>/dev/null || echo "0")
    if [[ "$file_size" -gt 26214400 ]]; then
        echo "Error: File too large (>25MB): $filename"
        echo "ERROR: File exceeds 25MB API limit" > "$output_file"
        return 1
    fi

    # Build API request
    local curl_args=(
        -s
        -X POST
        "$API_ENDPOINT"
        -H "Authorization: Bearer $OPENAI_API_KEY"
        -F "file=@$input_file"
        -F "model=$WHISPER_MODEL"
        -F "response_format=$RESPONSE_FORMAT"
    )

    # Add language if specified
    if [[ -n "$LANGUAGE" ]]; then
        curl_args+=(-F "language=$LANGUAGE")
    fi

    # Attempt transcription with retries
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        local response
        local http_code

        # Make API request
        response=$(curl "${curl_args[@]}" -w "\n%{http_code}" 2>/dev/null) || true
        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        # Check for success
        if [[ "$http_code" == "200" ]]; then
            if [[ "$RESPONSE_FORMAT" == "json" ]] || [[ "$RESPONSE_FORMAT" == "verbose_json" ]]; then
                echo "$response" > "$output_file"
            else
                echo "$response" > "$output_file"
            fi
            echo "[$(date '+%H:%M:%S')] Completed: $filename"
            return 0
        fi

        # Handle rate limiting
        if [[ "$http_code" == "429" ]]; then
            echo "[$(date '+%H:%M:%S')] Rate limited, waiting ${RETRY_DELAY}s... (attempt $attempt/$MAX_RETRIES)"
            sleep "$RETRY_DELAY"
            RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
        # Handle other errors
        elif [[ "$http_code" != "200" ]]; then
            echo "[$(date '+%H:%M:%S')] Error ($http_code) for $filename (attempt $attempt/$MAX_RETRIES)"
            if [[ $attempt -eq $MAX_RETRIES ]]; then
                echo "ERROR: HTTP $http_code - $response" > "$output_file"
                return 1
            fi
            sleep "$RETRY_DELAY"
        fi

        attempt=$((attempt + 1))
    done

    echo "[$(date '+%H:%M:%S')] Failed after $MAX_RETRIES attempts: $filename"
    return 1
}

# Export function and variables for parallel execution
export -f transcribe_file
export API_ENDPOINT OPENAI_API_KEY WHISPER_MODEL RESPONSE_FORMAT LANGUAGE
export MAX_RETRIES RETRY_DELAY

# ------------------------------------------------------------------------------
# Main processing
# ------------------------------------------------------------------------------

echo "=========================================="
echo "Transcribing audio chunks"
echo "=========================================="
echo "Chunks directory: $CHUNKS_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Settings:"
echo "  Model: $WHISPER_MODEL"
echo "  Format: $RESPONSE_FORMAT"
echo "  Language: ${LANGUAGE:-auto-detect}"
echo "  Parallel jobs: $PARALLEL_JOBS"
echo ""

# Find all audio chunks
CHUNKS=$(find "$CHUNKS_DIR" -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.m4a" -o -name "*.webm" \) | sort)
CHUNK_COUNT=$(echo "$CHUNKS" | wc -l | tr -d ' ')

if [[ -z "$CHUNKS" ]] || [[ "$CHUNK_COUNT" -eq 0 ]]; then
    echo "Error: No audio files found in $CHUNKS_DIR"
    exit 1
fi

echo "Found $CHUNK_COUNT chunk(s) to transcribe"
echo ""
echo "Starting transcription..."
echo ""

# Determine output extension based on response format
case "$RESPONSE_FORMAT" in
    json|verbose_json)
        OUTPUT_EXT="json"
        ;;
    srt)
        OUTPUT_EXT="srt"
        ;;
    vtt)
        OUTPUT_EXT="vtt"
        ;;
    *)
        OUTPUT_EXT="txt"
        ;;
esac

# Process chunks
# Using a simple loop with background jobs for parallelism
RUNNING_JOBS=0
PIDS=()

for chunk in $CHUNKS; do
    chunk_name=$(basename "$chunk" | sed 's/\.[^.]*$//')
    output_file="${OUTPUT_DIR}/${chunk_name}.${OUTPUT_EXT}"

    # Skip if already transcribed
    if [[ -f "$output_file" ]] && [[ $(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file") -gt 0 ]]; then
        if ! grep -q "^ERROR:" "$output_file" 2>/dev/null; then
            echo "[SKIP] Already transcribed: $(basename "$chunk")"
            continue
        fi
    fi

    # Start transcription in background
    transcribe_file "$chunk" "$output_file" &
    PIDS+=($!)
    RUNNING_JOBS=$((RUNNING_JOBS + 1))

    # Wait if we've reached the parallel job limit
    if [[ $RUNNING_JOBS -ge $PARALLEL_JOBS ]]; then
        wait "${PIDS[0]}" || true
        PIDS=("${PIDS[@]:1}")
        RUNNING_JOBS=$((RUNNING_JOBS - 1))
    fi
done

# Wait for remaining jobs
for pid in "${PIDS[@]}"; do
    wait "$pid" || true
done

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

echo ""
echo "=========================================="
echo "Transcription complete!"
echo "=========================================="
echo "Output directory: $OUTPUT_DIR"
echo ""

# Count results
SUCCESS_COUNT=$(find "$OUTPUT_DIR" -name "*.${OUTPUT_EXT}" -type f ! -exec grep -l "^ERROR:" {} \; 2>/dev/null | wc -l | tr -d ' ')
ERROR_COUNT=$(find "$OUTPUT_DIR" -name "*.${OUTPUT_EXT}" -type f -exec grep -l "^ERROR:" {} \; 2>/dev/null | wc -l | tr -d ' ')

echo "Results:"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed: $ERROR_COUNT"
echo ""

# List any failures
if [[ "$ERROR_COUNT" -gt 0 ]]; then
    echo "Failed transcriptions:"
    find "$OUTPUT_DIR" -name "*.${OUTPUT_EXT}" -type f -exec grep -l "^ERROR:" {} \; 2>/dev/null | while read f; do
        echo "  - $(basename "$f"): $(head -1 "$f")"
    done
fi
