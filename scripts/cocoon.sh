#!/usr/bin/env bash
# Cocoon CLI helper - Confidential AI inference via TEE

ENDPOINT="${COCOON_ENDPOINT:-http://127.0.0.1:10000}"

# Parse named args from positional args
# Usage: parse_args "$@" after shifting past the command and message
parse_args() {
    MODEL="" MAX_TOKENS="512" TEMPERATURE="0.7"
    MAX_COEFF="" TIMEOUT="" DEBUG=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) MODEL="$2"; shift 2 ;;
            --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
            --temperature) TEMPERATURE="$2"; shift 2 ;;
            --max-coefficient) MAX_COEFF="$2"; shift 2 ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
            --debug) DEBUG="true"; shift ;;
            *) shift ;;
        esac
    done
}

# Auto-detect model from /v1/models if not specified
resolve_model() {
    if [[ -n "$MODEL" ]]; then
        echo "$MODEL"
        return
    fi
    local resp
    resp=$(curl -s --max-time 5 "${ENDPOINT}/v1/models" 2>/dev/null)
    if command -v jq &>/dev/null; then
        echo "$resp" | jq -r '.data[0].id // empty' 2>/dev/null
    else
        echo "$resp" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
    fi
}

# Build optional Cocoon-specific JSON fields
cocoon_extras() {
    local extras=""
    [[ -n "$MAX_COEFF" ]] && extras="${extras},\"max_coefficient\":${MAX_COEFF}"
    [[ -n "$TIMEOUT" ]] && extras="${extras},\"timeout\":${TIMEOUT}"
    [[ "$DEBUG" == "true" ]] && extras="${extras},\"enable_debug\":true"
    echo "$extras"
}

case "${1:-}" in
    health)
        echo "Checking Cocoon at ${ENDPOINT}..."
        resp=$(curl -s --max-time 5 "${ENDPOINT}/stats" 2>/dev/null)
        if [[ -n "$resp" ]]; then
            echo "OK"
            echo "$resp"
        else
            echo "ERROR: Cocoon client not responding at ${ENDPOINT}"
            exit 1
        fi
        ;;

    models)
        resp=$(curl -s --max-time 10 "${ENDPOINT}/v1/models" 2>/dev/null)
        if [[ -z "$resp" ]]; then
            echo "ERROR: No response from ${ENDPOINT}/v1/models"
            exit 1
        fi
        echo "$resp"
        ;;

    chat)
        message="$2"
        if [[ -z "$message" ]]; then
            echo "Usage: cocoon.sh chat \"message\" [--model M] [--max-tokens N] [--temperature T]"
            exit 1
        fi
        shift 2
        parse_args "$@"
        model=$(resolve_model)
        if [[ -z "$model" ]]; then
            echo "ERROR: No model available. Specify --model or ensure Cocoon has loaded models."
            exit 1
        fi
        extras=$(cocoon_extras)
        # Escape message for JSON
        escaped=$(printf '%s' "$message" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$message")
        # Remove outer quotes if python3 added them, we add our own
        escaped=${escaped#\"}
        escaped=${escaped%\"}

        curl -s "${ENDPOINT}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${escaped}\"}],\"max_completion_tokens\":${MAX_TOKENS},\"temperature\":${TEMPERATURE}${extras}}"
        ;;

    stream)
        message="$2"
        if [[ -z "$message" ]]; then
            echo "Usage: cocoon.sh stream \"message\" [--model M] [--max-tokens N] [--temperature T]"
            exit 1
        fi
        shift 2
        parse_args "$@"
        model=$(resolve_model)
        if [[ -z "$model" ]]; then
            echo "ERROR: No model available. Specify --model or ensure Cocoon has loaded models."
            exit 1
        fi
        extras=$(cocoon_extras)
        escaped=$(printf '%s' "$message" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$message")
        escaped=${escaped#\"}
        escaped=${escaped%\"}

        curl -sN "${ENDPOINT}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${escaped}\"}],\"max_completion_tokens\":${MAX_TOKENS},\"temperature\":${TEMPERATURE},\"stream\":true,\"stream_options\":{\"include_usage\":true}${extras}}"
        ;;

    complete)
        prompt="$2"
        if [[ -z "$prompt" ]]; then
            echo "Usage: cocoon.sh complete \"prompt\" [--model M] [--max-tokens N] [--temperature T]"
            exit 1
        fi
        shift 2
        parse_args "$@"
        model=$(resolve_model)
        if [[ -z "$model" ]]; then
            echo "ERROR: No model available. Specify --model or ensure Cocoon has loaded models."
            exit 1
        fi
        extras=$(cocoon_extras)
        escaped=$(printf '%s' "$prompt" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$prompt")
        escaped=${escaped#\"}
        escaped=${escaped%\"}

        curl -s "${ENDPOINT}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${model}\",\"prompt\":\"${escaped}\",\"max_tokens\":${MAX_TOKENS},\"temperature\":${TEMPERATURE}${extras}}"
        ;;

    stats)
        resp=$(curl -s --max-time 10 "${ENDPOINT}/jsonstats" 2>/dev/null)
        if [[ -z "$resp" ]]; then
            echo "ERROR: No response from ${ENDPOINT}/jsonstats"
            exit 1
        fi
        echo "$resp"
        ;;

    *)
        echo "Cocoon CLI - Confidential AI inference via TEE"
        echo ""
        echo "Usage: cocoon.sh [command] [args]"
        echo ""
        echo "Commands:"
        echo "  health                         Check if Cocoon client is running"
        echo "  models                         List available models"
        echo "  chat \"message\" [opts]          Chat completion"
        echo "  stream \"message\" [opts]        Streaming chat completion"
        echo "  complete \"prompt\" [opts]       Text completion"
        echo "  stats                          Get JSON stats"
        echo ""
        echo "Options (for chat/stream/complete):"
        echo "  --model NAME                   Model name"
        echo "  --max-tokens N                 Max completion tokens (default: 512)"
        echo "  --temperature T                Temperature 0-2 (default: 0.7)"
        echo "  --max-coefficient N            Max worker cost coefficient"
        echo "  --timeout N                    Request timeout (seconds)"
        echo "  --debug                        Enable debug info"
        echo ""
        echo "Environment:"
        echo "  COCOON_ENDPOINT                Override endpoint (default: http://127.0.0.1:10000)"
        echo ""
        echo "Examples:"
        echo "  cocoon.sh chat \"Hello world\""
        echo "  cocoon.sh stream \"Write a poem\" --model Qwen/Qwen3-8B --max-tokens 200"
        echo "  cocoon.sh stats"
        ;;
esac
