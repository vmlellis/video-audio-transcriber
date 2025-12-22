# Video Audio Transcriber

A command-line tool to extract audio from video files, process it, and transcribe using OpenAI's Whisper API.

## Overview

This project provides a complete pipeline for transcribing video content:

1. **Extract audio** from video files
2. **Remove silence** to reduce processing time and costs
3. **Compress audio** for optimal API compatibility
4. **Split into chunks** (30-minute segments for API limits)
5. **Transcribe** each chunk via OpenAI Whisper API
6. **Merge** all transcriptions into a single output

## Motivation

This tool is designed for **local-first, desktop processing** with the following goals:

- **Privacy**: Process sensitive content locally before sending to APIs
- **Control**: Full control over audio preprocessing and quality
- **Cost efficiency**: Remove silence and optimize audio before transcription
- **Reliability**: Chunk-based processing allows resuming failed transcriptions
- **Transparency**: Clear, debuggable bash scripts you can inspect and modify

This is a **prototype** that will evolve into a full desktop application.

## Requirements

### System Dependencies

- **Bash** (4.0+)
- **ffmpeg** (with ffprobe)
- **curl**
- **jq** (for JSON processing)

### Installation

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg curl jq

# macOS (using Homebrew)
brew install ffmpeg curl jq

# Arch Linux
sudo pacman -S ffmpeg curl jq
```

### API Requirements

- **OpenAI API Key** with access to the Whisper API
- Sufficient API credits for transcription

## Environment Variables

```bash
# Required
export OPENAI_API_KEY="sk-your-api-key-here"

# Optional (with defaults)
export SILENCE_THRESHOLD="0.03"      # Silence detection threshold (0-1)
export SILENCE_DURATION="2.0"        # Minimum silence duration to remove (seconds)
export CHUNK_DURATION="1800"         # Chunk duration in seconds (default: 30 minutes)
export AUDIO_BITRATE="64k"           # Compressed audio bitrate
export PARALLEL_JOBS="2"             # Number of parallel transcription jobs
```

## Usage

### Quick Start (Full Pipeline)

```bash
# Set your API key
export OPENAI_API_KEY="sk-your-key"

# Run the complete pipeline
./scripts/run_pipeline.sh input/my_video.mp4
```

### Step-by-Step Usage

You can run each step individually for debugging or custom workflows:

```bash
# 1. Extract audio from video
./scripts/extract_audio.sh input/video.mp4 output/audio_raw.wav

# 2. Remove long silences
./scripts/remove_silence.sh output/audio_raw.wav output/audio_trimmed.wav

# 3. Compress audio
./scripts/compress_audio.sh output/audio_trimmed.wav output/audio_compressed.mp3

# 4. Split into 30-minute chunks
./scripts/split_audio.sh output/audio_compressed.mp3 output/chunks/

# 5. Transcribe all chunks (parallel)
./scripts/transcribe_chunks.sh output/chunks/ output/transcriptions/

# 6. Merge all transcriptions
./scripts/merge_transcriptions.sh output/transcriptions/ output/final_transcription.txt
```

### Example Command

```bash
# Process a lecture video
export OPENAI_API_KEY="sk-proj-xxxxx"
./scripts/run_pipeline.sh input/lecture_2024.mp4

# Output will be in: output/final_transcription.txt
```

## Output Structure

After running the pipeline:

```
output/
├── audio_raw.wav              # Extracted audio (optional, can be deleted)
├── audio_trimmed.wav          # Silence removed
├── audio_compressed.mp3       # Compressed for transcription
├── chunks/
│   ├── chunk_001.mp3
│   ├── chunk_002.mp3
│   └── ...
├── transcriptions/
│   ├── chunk_001.txt
│   ├── chunk_002.txt
│   └── ...
└── final_transcription.txt    # Merged final output
```

## Performance Notes

### Processing Time

- Audio extraction: ~1-2 minutes per hour of video
- Silence removal: ~2-5 minutes per hour (depends on content)
- Compression: ~1-2 minutes per hour
- Transcription: ~1-2 minutes per 30-minute chunk (API dependent)

### API Costs

- OpenAI Whisper API charges ~$0.006 per minute of audio
- A 2-hour video might cost approximately $0.72
- Silence removal can reduce costs by 10-40% depending on content

### File Size Limits

- OpenAI API accepts files up to **25MB**
- Chunks are compressed to ~64kbps to stay well under this limit
- 30-minute chunks at 64kbps ≈ 14MB (safe margin)

### Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| Higher compression | Smaller files, lower costs | Slightly reduced accuracy |
| Larger chunks | Fewer API calls | Risk of hitting size limits |
| More parallel jobs | Faster processing | Higher momentary API load |

## Troubleshooting

### Common Issues

**"ffmpeg: command not found"**
```bash
# Install ffmpeg for your system (see Requirements)
```

**"OPENAI_API_KEY not set"**
```bash
export OPENAI_API_KEY="sk-your-key-here"
```

**"File too large" API error**
```bash
# Reduce chunk duration or increase compression
export CHUNK_DURATION="900"   # 15 minutes
export AUDIO_BITRATE="48k"    # Higher compression
```

**"Rate limit exceeded"**
```bash
# Reduce parallel jobs
export PARALLEL_JOBS="1"
```

## Disclaimer

> ⚠️ **This is a prototype/proof-of-concept.**
>
> - Not production-ready
> - Error handling is basic
> - No resume functionality for interrupted pipelines
> - API costs are your responsibility
> - Always review transcriptions for accuracy
>
> Use at your own risk. This project is intended for learning and experimentation.

## License

MIT License
