#!/usr/bin/env bash
set -euo pipefail

# Cocoon CLI — Confidential AI inference via TEE
ENDPOINT="${COCOON_ENDPOINT:-http://127.0.0.1:10000}"

# -- Temp file handling (race-safe) --
_tmpfile=""
_cleanup() { [[ -n "$_tmpfile" ]] && rm -f "$_tmpfile"; }
trap _cleanup EXIT

_mktmp() {
    _tmpfile=$(mktemp) || { echo "ERROR: Cannot create temp file" >&2; exit 1; }
    echo "$_tmpfile"
}

# -- Shared HTTP helper --
# curl_checked URL [CURL_FLAGS...]
# Sets: _http_code, _http_body
_http_code="" _http_body=""
curl_checked() {
    local url="$1"; shift
    local tmp
    tmp=$(_mktmp)
    _http_code=$(curl -s -o "$tmp" -w "%{http_code}" --max-time 10 "$@" "$url" 2>/dev/null) || _http_code="000"
    _http_body=$(cat "$tmp" 2>/dev/null) || _http_body=""
}

# -- JSON escaping (no outer quotes) --
json_escape() {
    local raw="$1"
    if command -v jq &>/dev/null; then
        printf '%s' "$raw" | jq -Rs . | sed 's/^"//;s/"$//'
    elif command -v python3 &>/dev/null; then
        printf '%s' "$raw" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read())[1:-1])'
    else
        printf '%s' "$raw" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
    fi
}

# -- Arg parsing --
MODEL="" MAX_TOKENS="512" TEMPERATURE="0.7"
MAX_COEFF="" TIMEOUT="" DEBUG=""

parse_args() {
    MODEL="" MAX_TOKENS="512" TEMPERATURE="0.7"
    MAX_COEFF="" TIMEOUT="" DEBUG=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)          MODEL="$2"; shift 2 ;;
            --max-tokens)     MAX_TOKENS="$2"; shift 2 ;;
            --temperature)    TEMPERATURE="$2"; shift 2 ;;
            --max-coefficient) MAX_COEFF="$2"; shift 2 ;;
            --timeout)        TIMEOUT="$2"; shift 2 ;;
            --debug)          DEBUG="true"; shift ;;
            *)  echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        esac
    done
    # Validate numerics
    if [[ -n "$MAX_COEFF" ]] && ! [[ "$MAX_COEFF" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --max-coefficient must be a non-negative integer, got: $MAX_COEFF" >&2; exit 1
    fi
    if [[ -n "$TIMEOUT" ]] && ! [[ "$TIMEOUT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "ERROR: --timeout must be a number, got: $TIMEOUT" >&2; exit 1
    fi
}

# -- Auto-detect model --
resolve_model() {
    if [[ -n "$MODEL" ]]; then
        echo "$MODEL"
        return
    fi
    local resp
    resp=$(curl -s --max-time 5 "${ENDPOINT}/v1/models" 2>/dev/null) || true
    if command -v jq &>/dev/null; then
        echo "$resp" | jq -r '.data[0].id // empty' 2>/dev/null
    else
        echo "$resp" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
    fi
}

# -- Cocoon-specific JSON fields --
cocoon_extras() {
    local extras=""
    [[ -n "$MAX_COEFF" ]] && extras="${extras},\"max_coefficient\":${MAX_COEFF}"
    [[ -n "$TIMEOUT" ]]   && extras="${extras},\"timeout\":${TIMEOUT}"
    [[ "$DEBUG" == "true" ]] && extras="${extras},\"enable_debug\":true"
    echo "$extras"
}

# -- Unified inference runner --
# _run_inference MODE TEXT [extra_args...]
#   MODE: chat | stream | complete
_run_inference() {
    local mode="$1" text="$2"
    shift 2
    parse_args "$@"

    local model
    model=$(resolve_model)
    model=$(echo "$model" | xargs) # trim whitespace
    if [[ -z "$model" ]]; then
        echo "ERROR: No model available. Specify --model or ensure Cocoon has loaded models." >&2
        exit 1
    fi

    local extras escaped_text escaped_model
    extras=$(cocoon_extras)
    escaped_text=$(json_escape "$text")
    escaped_model=$(json_escape "$model")

    case "$mode" in
        chat)
            curl -s "${ENDPOINT}/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"${escaped_model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${escaped_text}\"}],\"max_completion_tokens\":${MAX_TOKENS},\"temperature\":${TEMPERATURE}${extras}}"
            echo
            ;;
        stream)
            curl -sN "${ENDPOINT}/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"${escaped_model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${escaped_text}\"}],\"max_completion_tokens\":${MAX_TOKENS},\"temperature\":${TEMPERATURE},\"stream\":true,\"stream_options\":{\"include_usage\":true}${extras}}"
            echo
            ;;
        complete)
            curl -s "${ENDPOINT}/v1/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"${escaped_model}\",\"prompt\":\"${escaped_text}\",\"max_tokens\":${MAX_TOKENS},\"temperature\":${TEMPERATURE}${extras}}"
            echo
            ;;
    esac
}

# -- Commands --
case "${1:-}" in
    health)
        echo "Checking Cocoon at ${ENDPOINT}..."
        curl_checked "${ENDPOINT}/jsonstats" --max-time 5
        if [[ "$_http_code" == "200" ]]; then
            echo "OK (HTTP ${_http_code})"
            echo "$_http_body"
        elif [[ "$_http_code" == "000" ]]; then
            echo "ERROR: Cocoon client not responding at ${ENDPOINT}" >&2
            exit 1
        else
            echo "ERROR: Cocoon returned HTTP ${_http_code}" >&2
            [[ -n "$_http_body" ]] && echo "$_http_body"
            exit 1
        fi
        ;;

    models)
        curl_checked "${ENDPOINT}/v1/models"
        if [[ "$_http_code" != "200" ]]; then
            echo "ERROR: /v1/models returned HTTP ${_http_code}" >&2
            [[ -n "$_http_body" ]] && echo "$_http_body" >&2
            exit 1
        fi
        echo "$_http_body"
        ;;

    chat)
        [[ -z "${2:-}" ]] && { echo "Usage: cocoon.sh chat \"message\" [--model M] [--max-tokens N] [--temperature T]" >&2; exit 1; }
        _run_inference chat "$2" "${@:3}"
        ;;

    stream)
        [[ -z "${2:-}" ]] && { echo "Usage: cocoon.sh stream \"message\" [--model M] [--max-tokens N] [--temperature T]" >&2; exit 1; }
        _run_inference stream "$2" "${@:3}"
        ;;

    complete)
        [[ -z "${2:-}" ]] && { echo "Usage: cocoon.sh complete \"prompt\" [--model M] [--max-tokens N] [--temperature T]" >&2; exit 1; }
        _run_inference complete "$2" "${@:3}"
        ;;

    stats)
        curl_checked "${ENDPOINT}/jsonstats"
        if [[ "$_http_code" != "200" ]]; then
            echo "ERROR: /jsonstats returned HTTP ${_http_code}" >&2
            [[ -n "$_http_body" ]] && echo "$_http_body" >&2
            exit 1
        fi
        echo "$_http_body"
        ;;

    *)
        cat <<'HELP'
Cocoon CLI - Confidential AI inference via TEE

Usage: cocoon.sh [command] [args]

Commands:
  health                         Check if Cocoon client is running
  models                         List available models
  chat "message" [opts]          Chat completion
  stream "message" [opts]        Streaming chat completion
  complete "prompt" [opts]       Text completion
  stats                          Get JSON stats

Options (for chat/stream/complete):
  --model NAME                   Model name
  --max-tokens N                 Max completion tokens (default: 512)
  --temperature T                Temperature 0-2 (default: 0.7)
  --max-coefficient N            Max worker cost coefficient
  --timeout N                    Request timeout (seconds)
  --debug                        Enable debug info

Environment:
  COCOON_ENDPOINT                Override endpoint (default: http://127.0.0.1:10000)

Examples:
  cocoon.sh chat "Hello world"
  cocoon.sh stream "Write a poem" --model Qwen/Qwen3-8B --max-tokens 200
  cocoon.sh stats
HELP
        ;;
esac
