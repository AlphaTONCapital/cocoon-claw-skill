# Cocoon API Reference

## Base URL

Default: `http://127.0.0.1:10000` (Cocoon client HTTP port)

## Inference Endpoints

### Chat Completions
```
POST /v1/chat/completions
```

Body:
```json
{
  "model": "Qwen/Qwen3-8B",
  "messages": [{"role": "user", "content": "Hello"}],
  "max_completion_tokens": 512,
  "temperature": 0.7,
  "top_p": 1.0,
  "frequency_penalty": 0,
  "presence_penalty": 0,
  "stream": false,
  "stream_options": {"include_usage": true},
  "stop": ["<|endoftext|>"],
  "n": 1,
  "response_format": {"type": "text"}
}
```

### Text Completions
```
POST /v1/completions
```

Body:
```json
{
  "model": "Qwen/Qwen3-8B",
  "prompt": "The meaning of life is",
  "max_tokens": 512,
  "temperature": 0.7,
  "stream": false
}
```

### List Models
```
GET /v1/models
```

## Cocoon-Specific Fields

These fields are parsed by the Cocoon client and stripped before forwarding to the worker:

| Field | Type | Description |
|-------|------|-------------|
| `max_coefficient` | int | Max worker cost coefficient (0 = no limit) |
| `timeout` | float | Request timeout in seconds |
| `enable_debug` | bool | Include debug info (timing, worker details) in response |
| `request_guid` | string | Custom request tracking ID |

## Stats Endpoints

### Human-Readable Stats
```
GET /stats
```

### JSON Stats
```
GET /jsonstats
```

## Response Format

Standard OpenAI-compatible response:
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1700000000,
  "model": "Qwen/Qwen3-8B",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "..."},
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 50,
    "total_tokens": 60
  }
}
```

## Response Headers

| Header | Description |
|--------|-------------|
| `X-Cocoon-Client-Start` | Unix timestamp when request started |
| `X-Cocoon-Client-End` | Unix timestamp when request ended |

## Error Codes

| HTTP Status | Meaning |
|-------------|---------|
| 200 | Success |
| 400 | Invalid JSON or missing required fields |
| 504 | No available workers or timeout |
