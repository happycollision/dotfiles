#!/usr/bin/env zsh
# Test suite for killport zsh function
# Run from dotfiles repository root: ./test/killport-test.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
KILLPORT_FILE="$DOTFILES_ROOT/zsh/functions/killport"

SERVER_PID=""

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} %s\n" "$1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} %s\n" "$1"
  if [[ -n "${2:-}" ]]; then
    printf "  %s\n" "$2"
  fi
}

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill -9 "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

if [[ ! -f "$KILLPORT_FILE" ]]; then
  printf "${RED}killport function file not found:${NC} %s\n" "$KILLPORT_FILE"
  exit 1
fi

source "$KILLPORT_FILE"

get_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

printf "${YELLOW}Test Group: killport usage${NC}\n"
usage_output=$(killport 2>&1)
usage_status=$?
if [[ "$usage_status" -eq 1 ]] && echo "$usage_output" | grep -q "Usage: killport <port>"; then
  pass "killport without args shows usage and exits 1"
else
  fail "killport without args shows usage and exits 1" "status=$usage_status output=$usage_output"
fi

printf "\n${YELLOW}Test Group: no process on port${NC}\n"
empty_port=$(get_free_port)
none_output=$(killport "$empty_port" 2>&1)
none_status=$?
if [[ "$none_status" -eq 0 ]] && echo "$none_output" | grep -q "No processes found on port $empty_port"; then
  pass "killport on unused port exits 0 with message"
else
  fail "killport on unused port exits 0 with message" "status=$none_status output=$none_output"
fi

printf "\n${YELLOW}Test Group: kill active listener${NC}\n"
active_port=$(get_free_port)
python3 -m http.server "$active_port" --bind 127.0.0.1 >/dev/null 2>&1 &
SERVER_PID=$!

ready=0
for _ in {1..200}; do
  if lsof -ti :"$active_port" >/dev/null 2>&1; then
    ready=1
    break
  fi
done

if [[ "$ready" -ne 1 ]]; then
  fail "test server started on chosen port" "port=$active_port pid=$SERVER_PID"
  exit 1
fi

kill_output=$(killport "$active_port" 2>&1)
kill_status=$?

if [[ "$kill_status" -ne 0 ]]; then
  fail "killport returns success when killing active listener" "status=$kill_status output=$kill_output"
elif lsof -ti :"$active_port" >/dev/null 2>&1; then
  fail "killport frees the port" "output=$kill_output"
elif kill -0 "$SERVER_PID" >/dev/null 2>&1; then
  fail "killport terminates listener process" "pid=$SERVER_PID output=$kill_output"
else
  pass "killport kills listener and frees the port"
fi

SERVER_PID=""

printf "\n${YELLOW}=== Test Summary ===${NC}\n"
printf "Tests run:    %s\n" "$TESTS_RUN"
printf "Tests passed: %s\n" "$TESTS_PASSED"
printf "Tests failed: %s\n" "$TESTS_FAILED"

if [[ "$TESTS_FAILED" -eq 0 ]]; then
  printf "\n${GREEN}All tests passed!${NC}\n"
  exit 0
else
  printf "\n${RED}Some tests failed.${NC}\n"
  exit 1
fi
