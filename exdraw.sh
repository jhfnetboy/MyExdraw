#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUNNEL_CONFIG_REL="cloudflared/config.yml"
TUNNEL_PID_FILE="${TMPDIR:-/tmp}/myexdraw-cloudflared.pid"
TUNNEL_LOG_FILE="${TMPDIR:-/tmp}/myexdraw-cloudflared.log"
PUBLIC_DOMAIN_BASE="${EXDRAW_PUBLIC_DOMAIN_BASE:-https://myexdraw.aastar.io}"

usage() {
  cat <<'EOF'
Usage: ./exdraw.sh <command>

Commands:
  docker   Show local docker status (no build, no start)
  tunnel   Restart cloudflared tunnel
  test     Curl public domain health

Examples:
  ./exdraw.sh docker
  ./exdraw.sh tunnel
  ./exdraw.sh test
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local pid="$!"

  local elapsed=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [[ "$elapsed" -ge "$seconds" ]]; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      sleep 1 || true
      kill -KILL "$pid" >/dev/null 2>&1 || true
      wait "$pid" || true
      return 124
    fi
    sleep 1 || true
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

is_tunnel_running() {
  if [[ -f "$TUNNEL_PID_FILE" ]]; then
    local pid
    pid="$(cat "$TUNNEL_PID_FILE" 2>/dev/null || true)"
    [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
    return $?
  fi
  return 1
}

start_tunnel() {
  require_cmd cloudflared
  cd "$ROOT_DIR"

  if [[ ! -f "$TUNNEL_CONFIG_REL" ]]; then
    echo "Missing tunnel config: $ROOT_DIR/$TUNNEL_CONFIG_REL" >&2
    exit 1
  fi

  nohup cloudflared tunnel --config "./$TUNNEL_CONFIG_REL" run >"$TUNNEL_LOG_FILE" 2>&1 &
  echo "$!" >"$TUNNEL_PID_FILE"
  echo "Tunnel started (pid $!)"
  echo "Log: $TUNNEL_LOG_FILE"
}

stop_tunnel() {
  if is_tunnel_running; then
    local pid
    pid="$(cat "$TUNNEL_PID_FILE")"
    kill "$pid" || true
    rm -f "$TUNNEL_PID_FILE" || true
    echo "Tunnel stopped (pid $pid)"
    return 0
  fi

  rm -f "$TUNNEL_PID_FILE" || true
}

curl_code() {
  require_cmd curl
  local url="$1"
  curl --connect-timeout 2 --max-time 8 -sS -o /dev/null -w "HTTP %{http_code}  ${url}\n" "$url" || echo "HTTP ???  ${url}"
}

restart_tunnel() {
  require_cmd cloudflared
  cd "$ROOT_DIR"

  stop_tunnel
  require_cmd pkill
  pkill -f "cloudflared tunnel --config .*/${TUNNEL_CONFIG_REL} run" >/dev/null 2>&1 || true
  start_tunnel
}

test_public_domain() {
  curl_code "${PUBLIC_DOMAIN_BASE}/"
  curl_code "${PUBLIC_DOMAIN_BASE}/api/v2/"
}

docker_status() {
  require_cmd docker
  cd "$ROOT_DIR"

  if run_with_timeout 5 docker info >/dev/null 2>&1; then
    echo "Docker: OK"
  else
    echo "Docker: NOT RUNNING" >&2
    exit 1
  fi

  docker compose ps || true
  curl_code "http://localhost:9887/"
  curl_code "http://localhost:9888/api/v2/"
}

cmd="${1:-}"
case "$cmd" in
  docker)
    docker_status
    ;;
  tunnel)
    restart_tunnel
    ;;
  test)
    test_public_domain
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
