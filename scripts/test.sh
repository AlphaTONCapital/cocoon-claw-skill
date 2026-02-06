#!/usr/bin/env bash
set -euo pipefail

# Test suite for cocoon.sh
# Uses a tiny python3 mock HTTP server — no live Cocoon needed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COCOON="$SCRIPT_DIR/cocoon.sh"
PASS=0 FAIL=0 SKIP=0

# -- Helpers --
_green() { printf '\033[32m%s\033[0m\n' "$*"; }
_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
_yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

assert_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        _green "  PASS: $desc"; ((PASS++))
    else
        _red "  FAIL: $desc"; ((FAIL++))
    fi
}

assert_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        _red "  FAIL (expected error): $desc"; ((FAIL++))
    else
        _green "  PASS: $desc"; ((PASS++))
    fi
}

assert_contains() {
    local desc="$1" expected="$2"; shift 2
    local out
    out=$("$@" 2>&1) || true
    if [[ "$out" == *"$expected"* ]]; then
        _green "  PASS: $desc"; ((PASS++))
    else
        _red "  FAIL: $desc"
        _red "    expected to contain: $expected"
        _red "    got: ${out:0:200}"; ((FAIL++))
    fi
}

assert_not_contains() {
    local desc="$1" unexpected="$2"; shift 2
    local out
    out=$("$@" 2>&1) || true
    if [[ "$out" != *"$unexpected"* ]]; then
        _green "  PASS: $desc"; ((PASS++))
    else
        _red "  FAIL: $desc"
        _red "    should NOT contain: $unexpected"; ((FAIL++))
    fi
}

# -- Mock HTTP server --
MOCK_PORT=""
MOCK_PID=""

start_mock() {
    local status="${1:-200}" body="${2:-{}}" content_type="${3:-application/json}"
    # Find a free port
    MOCK_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
    python3 -c "
import http.server, sys, threading

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(${status})
        self.send_header('Content-Type', '${content_type}')
        self.end_headers()
        self.wfile.write(b'''${body}''')
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)
        # Write received body to a temp file for inspection
        with open('/tmp/cocoon_test_payload', 'wb') as f:
            f.write(body)
        self.send_response(${status})
        self.send_header('Content-Type', '${content_type}')
        self.end_headers()
        self.wfile.write(b'''${body}''')
    def log_message(self, *a): pass

s = http.server.HTTPServer(('127.0.0.1', ${MOCK_PORT}), H)
s.handle_request()  # serve exactly 1 request then exit
" &
    MOCK_PID=$!
    sleep 0.2  # let it bind
}

stop_mock() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
    MOCK_PID=""
}

cleanup() {
    stop_mock
    rm -f /tmp/cocoon_test_payload
}
trap cleanup EXIT

# ============================================================
echo "=== json_escape tests ==="
# ============================================================

# Extract json_escape function from cocoon.sh and source it
_fn_file=$(mktemp)
sed -n '/^json_escape()/,/^}/p' "$COCOON" > "$_fn_file"
source "$_fn_file"
rm -f "$_fn_file"

result=$(json_escape 'hello world')
if [[ "$result" == 'hello world' ]]; then
    _green "  PASS: simple string passthrough"; ((PASS++))
else
    _red "  FAIL: simple string — got: $result"; ((FAIL++))
fi

result=$(json_escape 'say "hello"')
if [[ "$result" == 'say \"hello\"' ]]; then
    _green "  PASS: escapes double quotes"; ((PASS++))
else
    _red "  FAIL: escapes double quotes — got: $result"; ((FAIL++))
fi

result=$(json_escape 'back\slash')
if [[ "$result" == 'back\\slash' ]]; then
    _green "  PASS: escapes backslashes"; ((PASS++))
else
    _red "  FAIL: escapes backslashes — got: $result"; ((FAIL++))
fi

result=$(json_escape $'line1\nline2')
if [[ "$result" == 'line1\nline2' ]]; then
    _green "  PASS: escapes newlines"; ((PASS++))
else
    _red "  FAIL: escapes newlines — got: $result"; ((FAIL++))
fi

result=$(json_escape $'tab\there')
if [[ "$result" == 'tab\there' ]]; then
    _green "  PASS: escapes tabs"; ((PASS++))
else
    _red "  FAIL: escapes tabs — got: $result"; ((FAIL++))
fi

result=$(json_escape '')
if [[ "$result" == '' ]]; then
    _green "  PASS: empty string"; ((PASS++))
else
    _red "  FAIL: empty string — got: $result"; ((FAIL++))
fi

# ============================================================
echo ""
echo "=== parse_args validation tests ==="
# ============================================================

assert_fail "unknown flag rejected" \
    "$COCOON" chat "hello" --model test --modle typo

assert_fail "--max-coefficient rejects non-integer" \
    "$COCOON" chat "hello" --model test --max-coefficient abc

assert_fail "--timeout rejects non-number" \
    "$COCOON" chat "hello" --model test --timeout "not_a_number"

# Valid numerics — use mock server so the command actually succeeds end-to-end
rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"ok"}}]}'
assert_ok "--max-coefficient accepts integer" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat 'hi' --model test --max-coefficient 5
stop_mock

rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"ok"}}]}'
assert_ok "--timeout accepts decimal" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat 'hi' --model test --timeout 30.5
stop_mock

# --max-tokens / --temperature validation
assert_fail "--max-tokens rejects non-integer" \
    "$COCOON" chat "hello" --model test --max-tokens abc

assert_fail "--temperature rejects non-number" \
    "$COCOON" chat "hello" --model test --temperature banana

rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"ok"}}]}'
assert_ok "--max-tokens accepts integer" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat 'hi' --model test --max-tokens 100
stop_mock

rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"ok"}}]}'
assert_ok "--temperature accepts decimal" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat 'hi' --model test --temperature 0.5
stop_mock

# ============================================================
echo ""
echo "=== health command tests ==="
# ============================================================

start_mock 200 '{"status":"ok","queries":42}'
assert_contains "health 200 → OK" "OK (HTTP 200)" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" health
stop_mock

start_mock 502 '{"error":"no proxy"}'
assert_contains "health 502 → ERROR with code" "HTTP 502" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" health
stop_mock

assert_contains "health no server → ERROR" "not responding" \
    env COCOON_ENDPOINT="http://127.0.0.1:1" "$COCOON" health

# ============================================================
echo ""
echo "=== models command tests ==="
# ============================================================

start_mock 200 '{"data":[{"id":"Qwen/Qwen3-8B","object":"model"}]}'
assert_contains "models 200 → returns body" "Qwen/Qwen3-8B" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" models
stop_mock

start_mock 500 '{"error":"internal"}'
assert_contains "models 500 → ERROR" "HTTP 500" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" models
stop_mock

# ============================================================
echo ""
echo "=== stats command tests ==="
# ============================================================

start_mock 200 '{"stats":{"queries":100}}'
assert_contains "stats 200 → returns body" "queries" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" stats
stop_mock

start_mock 502 '{"error":"down"}'
assert_contains "stats 502 → ERROR" "HTTP 502" \
    env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" stats
stop_mock

# ============================================================
echo ""
echo "=== chat command tests ==="
# ============================================================

assert_fail "chat missing message → error" \
    "$COCOON" chat

# Test payload structure
rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"hi"}}]}'
env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat "test message" --model TestModel --max-tokens 100 --temperature 0.5 >/dev/null 2>&1 || true
sleep 0.2
stop_mock

if [[ -f /tmp/cocoon_test_payload ]]; then
    payload=$(cat /tmp/cocoon_test_payload)
    # Verify key fields
    if [[ "$payload" == *'"model":"TestModel"'* ]]; then
        _green "  PASS: chat payload has model"; ((PASS++))
    else
        _red "  FAIL: chat payload missing model — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"max_completion_tokens":100'* ]]; then
        _green "  PASS: chat uses max_completion_tokens"; ((PASS++))
    else
        _red "  FAIL: chat missing max_completion_tokens — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"temperature":0.5'* ]]; then
        _green "  PASS: chat has temperature"; ((PASS++))
    else
        _red "  FAIL: chat missing temperature — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"test message"'* ]]; then
        _green "  PASS: chat has message content"; ((PASS++))
    else
        _red "  FAIL: chat missing message content — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" != *'"stream"'* ]]; then
        _green "  PASS: chat has no stream flag"; ((PASS++))
    else
        _red "  FAIL: chat should not have stream flag"; ((FAIL++))
    fi
    rm -f /tmp/cocoon_test_payload
else
    _red "  FAIL: no payload captured"; ((FAIL+=5))
fi

# ============================================================
echo ""
echo "=== stream command tests ==="
# ============================================================

rm -f /tmp/cocoon_test_payload
start_mock 200 'data: {"choices":[{"delta":{"content":"hi"}}]}'
env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" stream "stream test" --model TestModel >/dev/null 2>&1 || true
sleep 0.2
stop_mock

if [[ -f /tmp/cocoon_test_payload ]]; then
    payload=$(cat /tmp/cocoon_test_payload)
    if [[ "$payload" == *'"stream":true'* ]]; then
        _green "  PASS: stream payload has stream:true"; ((PASS++))
    else
        _red "  FAIL: stream missing stream:true — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"include_usage":true'* ]]; then
        _green "  PASS: stream has include_usage"; ((PASS++))
    else
        _red "  FAIL: stream missing include_usage — got: $payload"; ((FAIL++))
    fi
    rm -f /tmp/cocoon_test_payload
else
    _red "  FAIL: no stream payload captured"; ((FAIL+=2))
fi

# ============================================================
echo ""
echo "=== complete command tests ==="
# ============================================================

rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"text":"completed"}]}'
env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" complete "test prompt" --model TestModel --max-tokens 256 >/dev/null 2>&1 || true
sleep 0.2
stop_mock

if [[ -f /tmp/cocoon_test_payload ]]; then
    payload=$(cat /tmp/cocoon_test_payload)
    if [[ "$payload" == *'"prompt":"test prompt"'* ]]; then
        _green "  PASS: complete has prompt field"; ((PASS++))
    else
        _red "  FAIL: complete missing prompt — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"max_tokens":256'* ]]; then
        _green "  PASS: complete uses max_tokens (not max_completion_tokens)"; ((PASS++))
    else
        _red "  FAIL: complete should use max_tokens — got: $payload"; ((FAIL++))
    fi
    rm -f /tmp/cocoon_test_payload
else
    _red "  FAIL: no complete payload captured"; ((FAIL+=2))
fi

# ============================================================
echo ""
echo "=== cocoon_extras tests ==="
# ============================================================

rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"ok"}}]}'
env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat "test" --model M --max-coefficient 5 --timeout 30 --debug >/dev/null 2>&1 || true
sleep 0.2
stop_mock

if [[ -f /tmp/cocoon_test_payload ]]; then
    payload=$(cat /tmp/cocoon_test_payload)
    if [[ "$payload" == *'"max_coefficient":5'* ]]; then
        _green "  PASS: extras has max_coefficient"; ((PASS++))
    else
        _red "  FAIL: extras missing max_coefficient — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"timeout":30'* ]]; then
        _green "  PASS: extras has timeout"; ((PASS++))
    else
        _red "  FAIL: extras missing timeout — got: $payload"; ((FAIL++))
    fi
    if [[ "$payload" == *'"enable_debug":true'* ]]; then
        _green "  PASS: extras has enable_debug"; ((PASS++))
    else
        _red "  FAIL: extras missing enable_debug — got: $payload"; ((FAIL++))
    fi
    rm -f /tmp/cocoon_test_payload
else
    _red "  FAIL: no extras payload captured"; ((FAIL+=3))
fi

# ============================================================
echo ""
echo "=== resolve_model auto-detection tests ==="
# ============================================================

# Auto-detect model from /v1/models (mock returns models list for GET, then serves POST)
# We need two requests: GET /v1/models (resolve) + POST /v1/chat/completions (inference)
# Use a multi-request mock for this
MOCK_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
rm -f /tmp/cocoon_test_payload
python3 -c "
import http.server

class H(http.server.BaseHTTPRequestHandler):
    count = 0
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"data\":[{\"id\":\"AutoModel/Test-7B\",\"object\":\"model\"}]}')
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)
        with open('/tmp/cocoon_test_payload', 'wb') as f:
            f.write(body)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}')
    def log_message(self, *a): pass

s = http.server.HTTPServer(('127.0.0.1', ${MOCK_PORT}), H)
s.handle_request()  # GET /v1/models
s.handle_request()  # POST /v1/chat/completions
" &
MOCK_PID=$!
sleep 0.2

# Chat WITHOUT --model → should auto-detect AutoModel/Test-7B
env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat "auto test" >/dev/null 2>&1 || true
sleep 0.2
stop_mock

if [[ -f /tmp/cocoon_test_payload ]]; then
    payload=$(cat /tmp/cocoon_test_payload)
    if [[ "$payload" == *'"AutoModel/Test-7B"'* ]]; then
        _green "  PASS: resolve_model auto-detected model from /v1/models"; ((PASS++))
    else
        _red "  FAIL: resolve_model did not auto-detect — got: $payload"; ((FAIL++))
    fi
    rm -f /tmp/cocoon_test_payload
else
    _red "  FAIL: no payload for auto-detect test"; ((FAIL++))
fi

# No model available → should error
assert_contains "no model available → error" "No model available" \
    env COCOON_ENDPOINT="http://127.0.0.1:1" "$COCOON" chat "test"

# ============================================================
echo ""
echo "=== json_escape sed fallback test ==="
# ============================================================

# Test the sed fallback by hiding jq and python3 from PATH
_sed_result=$(PATH=/usr/bin:/bin bash -c '
    # Ensure only sed is available (no jq, no python3)
    unset -f json_escape 2>/dev/null
    '"$(sed -n '/^json_escape()/,/^}/p' "$COCOON")"'
    json_escape "say \"hello\" and back\\slash"
' 2>/dev/null) || true
if [[ "$_sed_result" == 'say \"hello\" and back\\slash' ]]; then
    _green "  PASS: sed fallback escapes quotes and backslashes"; ((PASS++))
else
    _red "  FAIL: sed fallback — got: $_sed_result"; ((FAIL++))
fi

# ============================================================
echo ""
echo "=== edge case tests ==="
# ============================================================

# Special characters in message
rm -f /tmp/cocoon_test_payload
start_mock 200 '{"choices":[{"message":{"content":"ok"}}]}'
env COCOON_ENDPOINT="http://127.0.0.1:${MOCK_PORT}" "$COCOON" chat 'He said "hello" & <bye>' --model M >/dev/null 2>&1 || true
sleep 0.2
stop_mock

if [[ -f /tmp/cocoon_test_payload ]]; then
    payload=$(cat /tmp/cocoon_test_payload)
    if [[ "$payload" == *'\"hello\"'* ]]; then
        _green "  PASS: special chars escaped in payload"; ((PASS++))
    else
        _red "  FAIL: special chars not escaped — got: $payload"; ((FAIL++))
    fi
    rm -f /tmp/cocoon_test_payload
else
    _red "  FAIL: no payload for special chars test"; ((FAIL++))
fi

# COCOON_ENDPOINT override
assert_contains "COCOON_ENDPOINT override" "not responding" \
    env COCOON_ENDPOINT="http://127.0.0.1:1" "$COCOON" health

# Help text
assert_contains "no args → help" "Usage: cocoon.sh" "$COCOON"
assert_contains "help mentions health" "health" "$COCOON"
assert_contains "help mentions chat" "chat" "$COCOON"

# ============================================================
echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "========================================="
[[ $FAIL -eq 0 ]] && _green "All tests passed!" || _red "Some tests failed."
exit $FAIL
