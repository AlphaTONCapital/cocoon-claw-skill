---
name: cocoon
description: Use Cocoon for confidential AI inference via TEE-protected workers on the TON blockchain. OpenAI-compatible API. Use when the user wants to run inference through Cocoon, check Cocoon status, list Cocoon models, or use decentralized/confidential/TEE compute.
metadata: {"openclaw":{"requires":{"bins":["curl"]}}}
---

# Cocoon Skill

Confidential AI inference through the [Cocoon](https://github.com/TelegramMessenger/cocoon) network. Models run in Intel TDX trusted execution environments with payments on TON.

## Prerequisites

A Cocoon client must be running locally (default `http://127.0.0.1:10000`). Override with `COCOON_ENDPOINT` env var.

## Scripts

Use the provided bash script in the `scripts/` directory:
- `cocoon.sh` - Main CLI tool for all Cocoon operations

## Common Operations

### Check Health
```bash
./scripts/cocoon.sh health
```

### List Models
```bash
./scripts/cocoon.sh models
```

### Chat Completion
```bash
./scripts/cocoon.sh chat "Explain quantum computing in one sentence"
./scripts/cocoon.sh chat "Translate to French: hello world" --model Qwen/Qwen3-8B --max-tokens 200
```

### Streaming Chat
```bash
./scripts/cocoon.sh stream "Write a haiku about the ocean"
```

### Text Completion
```bash
./scripts/cocoon.sh complete "The meaning of life is"
```

### Stats
```bash
./scripts/cocoon.sh stats
```

## Cocoon-Specific Options

These options can be appended to `chat`, `stream`, or `complete` commands:
- `--model NAME` - Model to use (default: auto-detected from `/v1/models`)
- `--max-tokens N` - Max completion tokens (default: 512)
- `--temperature T` - Sampling temperature 0-2 (default: 0.7)
- `--max-coefficient N` - Max worker cost coefficient
- `--timeout N` - Request timeout in seconds
- `--debug` - Enable debug info in response

## API Endpoints

See `references/api.md` for full API documentation.
