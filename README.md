# Cocoon Skill for OpenClaw

[![GitHub](https://img.shields.io/badge/GitHub-AlphaTONCapital%2Fcocoon--claw--skill-blue)](https://github.com/AlphaTONCapital/cocoon-claw-skill)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/works%20with-OpenClaw-orange)](https://openclaw.ai)

An [OpenClaw](https://openclaw.ai) skill that gives your AI agent access to [Cocoon](https://github.com/TelegramMessenger/cocoon) — confidential AI inference running in trusted execution environments on the TON blockchain.

## What is Cocoon?

[COCOON](https://github.com/TelegramMessenger/cocoon) (Confidential Compute Open Network) is a decentralized AI inference platform where:

- **GPU owners** earn TON by serving models inside Intel TDX enclaves
- **Developers** get low-cost, secure, and verifiable AI compute
- **Users** get AI with full privacy — requests and responses stay encrypted end-to-end

Models run inside hardware-attested trusted execution environments. Nobody — not the GPU operator, not the proxy, not anyone in between — can see your prompts or completions.

## What This Skill Does

This skill wraps the Cocoon client's OpenAI-compatible API into simple commands your OpenClaw agent can use:

- **Health checks** — Verify the Cocoon client is running
- **Model discovery** — List available models on the network
- **Chat completions** — Send messages, get responses
- **Streaming** — Real-time token-by-token output
- **Text completions** — Raw prompt completions
- **Stats** — Monitor usage and performance

## Why Use This?

| Without This Skill | With This Skill |
|---|---|
| Hand-craft curl to `localhost:10000/v1/chat/completions` | `cocoon.sh chat "Hello"` |
| Manually discover model names | Auto-detected from `/v1/models` |
| No streaming without careful flag management | `cocoon.sh stream "Write a poem"` |
| Parse raw JSON responses yourself | Structured output for agent consumption |
| Forget Cocoon-specific params | `--max-coefficient`, `--timeout`, `--debug` built in |

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌───────────┐     ┌──────────────────────┐
│  OpenClaw    │────▶│  Cocoon Client   │────▶│   Proxy   │────▶│  Worker (Intel TDX)  │
│  Agent       │     │  localhost:10000  │     │  RA-TLS   │     │  vLLM / SGLang + GPU │
└──────────────┘     └──────────────────┘     └───────────┘     └──────────────────────┘
     asks                 forwards              routes             runs model in TEE
     "chat ..."           via OpenAI API        to workers         returns completion
```

All traffic between Proxy and Worker is encrypted via **RA-TLS** (Remote Attestation TLS). The Worker's TEE image hash is verified on-chain before any request is routed to it.

## Quick Start

```bash
# 1. Install the skill
cd ~/oni/aton/logan/workspace/skills
git clone https://github.com/AlphaTONCapital/cocoon-claw-skill.git cocoon

# 2. Ensure a Cocoon client is running (default: localhost:10000)
#    Or set a custom endpoint:
export COCOON_ENDPOINT="http://your-cocoon-client:10000"

# 3. Check health
./cocoon/scripts/cocoon.sh health

# 4. Send your first request
./cocoon/scripts/cocoon.sh chat "What is confidential computing?"
```

## Usage

### For OpenClaw Agents

Once installed, your agent picks up the skill automatically:

```
You: "Ask Cocoon what models are available"
Agent: [Uses cocoon.sh models to list]

You: "Use Cocoon to summarize this document"
Agent: [Uses cocoon.sh chat with the document content]

You: "Stream a response from Cocoon about TON"
Agent: [Uses cocoon.sh stream for real-time output]
```

### Command Line Interface

```bash
# Health & status
./scripts/cocoon.sh health                    # Check if client is running
./scripts/cocoon.sh models                    # List available models
./scripts/cocoon.sh stats                     # Get JSON usage stats

# Inference
./scripts/cocoon.sh chat "message"            # Chat completion
./scripts/cocoon.sh stream "message"          # Streaming chat completion
./scripts/cocoon.sh complete "prompt"         # Text completion

# With options
./scripts/cocoon.sh chat "Hello" --model Qwen/Qwen3-8B --max-tokens 200 --temperature 0.5
./scripts/cocoon.sh stream "Write a haiku" --timeout 30 --debug
```

### Examples

```bash
# Quick chat
./scripts/cocoon.sh chat "Explain zero-knowledge proofs in one sentence"

# Stream a longer response
./scripts/cocoon.sh stream "Write a short story about a lobster on the blockchain" \
  --max-tokens 1000 --temperature 0.9

# Text completion with a specific model
./scripts/cocoon.sh complete "The future of decentralized AI is" \
  --model Qwen/Qwen3-8B --max-tokens 256
```

## Features

- **Minimal dependencies** — Requires only `curl`. Uses `jq` or `python3` for JSON escaping when available, falls back to `sed`
- **Auto model detection** — Discovers available models automatically
- **Streaming support** — Token-by-token output via SSE
- **Cocoon-specific params** — `--max-coefficient`, `--timeout`, `--debug`
- **Configurable endpoint** — `COCOON_ENDPOINT` env var
- **OpenAI-compatible** — Standard `/v1/chat/completions` API under the hood

## Repository Structure

```
cocoon-claw-skill/
├── README.md              # This file
├── LICENSE                # MIT License
├── SKILL.md               # OpenClaw skill definition
├── scripts/
│   ├── cocoon.sh          # CLI tool for all Cocoon operations
│   └── test.sh            # Test suite
└── references/
    └── api.md             # Complete Cocoon API reference
```

## How It Works

1. **OpenClaw loads SKILL.md** when you mention Cocoon or confidential inference
2. **Skill provides context** — API endpoints, usage patterns, available commands
3. **Agent calls `scripts/cocoon.sh`** with the appropriate command
4. **Script sends HTTP requests** to the local Cocoon client (`localhost:10000`)
5. **Cocoon client routes** through Proxy to a TEE-protected Worker, returns the result

## Configuration

| Variable | Default | Description |
|---|---|---|
| `COCOON_ENDPOINT` | `http://127.0.0.1:10000` | Cocoon client HTTP endpoint |

All configuration is via environment variables. No credentials are stored — the Cocoon client handles authentication and payment channels with the TON blockchain.

## Security

- **Trusted Execution** — All inference runs inside Intel TDX hardware enclaves
- **RA-TLS** — Proxy-to-Worker connections are encrypted and attestation-verified
- **On-chain verification** — Worker image hashes are registered in TON smart contracts
- **Local only** — This skill talks to your local Cocoon client; nothing leaves your machine until the client encrypts it
- **No credentials stored** — No API keys, tokens, or secrets in this repo

## Troubleshooting

### "Cocoon client not responding"
```bash
# Check if the client process is running
curl -s http://127.0.0.1:10000/stats

# Verify the endpoint
echo $COCOON_ENDPOINT
```

### "No model available"
- Ensure the Cocoon client is connected to at least one proxy with active workers
- Check `./scripts/cocoon.sh models` — if empty, no workers are serving models yet
- Try specifying a model explicitly: `--model Qwen/Qwen3-8B`

### "504 Gateway Timeout"
- No workers available on the network, or request timed out
- Try increasing timeout: `--timeout 60`
- Check network stats: `./scripts/cocoon.sh stats`

## Contributing

Contributions welcome. Open an issue or submit a PR.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT — See [LICENSE](LICENSE) file.

## Links

- **Cocoon**: https://github.com/TelegramMessenger/cocoon
- **OpenClaw**: https://openclaw.ai
- **TON**: https://ton.org
- **This Repo**: https://github.com/AlphaTONCapital/cocoon-claw-skill

---

Built by [AlphaTON Capital](https://github.com/AlphaTONCapital) — bridging AI agents and confidential compute.
