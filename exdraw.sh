#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCALIDRAW_DIR="$ROOT_DIR/vendor/excalidraw"
DEFAULT_PORTS=(5173 9887 9888)
TUNNEL_CONFIG_REL="cloudflared/config.yml"
TUNNEL_PID_FILE="${TMPDIR:-/tmp}/myexdraw-cloudflared.pid"
TUNNEL_LOG_FILE="${TMPDIR:-/tmp}/myexdraw-cloudflared.log"

usage() {
  cat <<'EOF'
Usage: ./exdraw.sh <command>

Commands:
  web:start         Start local web dev server (Vite) on :5173
  web:stop          Stop local web dev server on :5173
  web:open          Print local web URL
  web:test          Curl local web dev server (:5173)
  lint              Run eslint (yarn test:code)
  typecheck         Run TypeScript typecheck (yarn test:typecheck)
  build             Build excalidraw app (yarn build:app:docker)
  docker:build      Build local docker image (linux/amd64) as myexdraw-excalidraw:local
  docker:build:legacy  Build local docker image with DOCKER_BUILDKIT=0
  docker:ensure     Build image if missing, then start compose
  docker:up         Start docker compose stack
  docker:restart    Restart web+excalidraw services using current images
  docker:down       Stop docker compose stack
  docker:ps         Show docker compose status
  docker:clean      Stop stack and remove local images/volumes/cache
  ports:kill        Kill processes listening on ports (default: 5173 9887 9888)
  tunnel:start      Start cloudflared tunnel (background)
  tunnel:stop       Stop cloudflared tunnel
  tunnel:restart    Restart cloudflared tunnel
  local:test        Test localhost:9887 (web) and :9888 (storage)
  domain:test       Test https://myexdraw.aastar.io and /api/v2/
  full:check        ports:kill + docker:ensure + tunnel:restart + domain:test
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

kill_ports() {
  require_cmd lsof
  local ports=("$@")
  if [[ ${#ports[@]} -eq 0 ]]; then
    ports=("${DEFAULT_PORTS[@]}")
  fi

  local port
  for port in "${ports[@]}"; do
    local pids
    pids="$(lsof -ti "tcp:${port}" || true)"
    if [[ -n "$pids" ]]; then
      echo "$pids" | xargs kill -9 || true
      echo "Killed processes on :${port}"
    else
      echo "No process is listening on :${port}"
    fi
  done
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

  if is_tunnel_running; then
    echo "Tunnel already running (pid $(cat "$TUNNEL_PID_FILE"))"
    return 0
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

  echo "Tunnel not running"
  rm -f "$TUNNEL_PID_FILE" || true
}

curl_code() {
  require_cmd curl
  local url="$1"
  curl --connect-timeout 2 --max-time 8 -fsS -o /dev/null -w "HTTP %{http_code}  ${url}\n" "$url" || echo "HTTP ???  ${url}"
}

cmd="${1:-}"
case "$cmd" in
  web:start)
    require_cmd yarn
    cd "$EXCALIDRAW_DIR"
    exec yarn --no-default-rc --cwd ./excalidraw-app vite --host 0.0.0.0 --port 5173
    ;;
  web:stop)
    require_cmd lsof
    pids="$(lsof -ti tcp:5173 || true)"
    if [[ -z "$pids" ]]; then
      echo "No process is listening on :5173"
      exit 0
    fi
    echo "$pids" | xargs kill
    ;;
  web:open)
    echo "http://localhost:5173/"
    ;;
  web:test)
    curl_code "http://localhost:5173/"
    ;;
  lint)
    require_cmd yarn
    cd "$EXCALIDRAW_DIR"
    yarn test:code
    ;;
  typecheck)
    require_cmd yarn
    cd "$EXCALIDRAW_DIR"
    yarn test:typecheck
    ;;
  build)
    require_cmd yarn
    cd "$EXCALIDRAW_DIR"
    yarn build:app:docker
    ;;
  docker:build)
    require_cmd docker
    cd "$ROOT_DIR"
    docker buildx build --platform linux/amd64 -t myexdraw-excalidraw:local --load "$EXCALIDRAW_DIR"
    ;;
  docker:build:legacy)
    require_cmd docker
    cd "$ROOT_DIR"
    DOCKER_BUILDKIT=0 docker build -t myexdraw-excalidraw:local "$EXCALIDRAW_DIR"
    ;;
  docker:ensure)
    require_cmd docker
    cd "$ROOT_DIR"
    if ! docker image inspect myexdraw-excalidraw:local >/dev/null 2>&1; then
      docker buildx build --platform linux/amd64 -t myexdraw-excalidraw:local --load "$EXCALIDRAW_DIR"
    fi
    docker compose up -d
    docker compose ps
    ;;
  docker:up)
    require_cmd docker
    cd "$ROOT_DIR"
    docker compose up -d
    ;;
  docker:restart)
    require_cmd docker
    cd "$ROOT_DIR"
    docker compose up -d --force-recreate web excalidraw
    ;;
  docker:down)
    require_cmd docker
    cd "$ROOT_DIR"
    docker compose down
    ;;
  docker:ps)
    require_cmd docker
    cd "$ROOT_DIR"
    docker compose ps
    ;;
  docker:clean)
    require_cmd docker
    cd "$ROOT_DIR"
    docker compose down --remove-orphans --volumes || true
    docker image rm -f myexdraw-excalidraw:local || true
    docker image prune -af || true
    docker builder prune -af || true
    docker system prune -af --volumes || true
    ;;
  ports:kill)
    shift || true
    kill_ports "$@"
    ;;
  tunnel:start)
    start_tunnel
    ;;
  tunnel:stop)
    stop_tunnel
    ;;
  tunnel:restart)
    stop_tunnel
    start_tunnel
    ;;
  local:test)
    curl_code "http://localhost:9887/"
    curl_code "http://localhost:9888/"
    ;;
  domain:test)
    curl_code "https://myexdraw.aastar.io/"
    curl_code "https://myexdraw.aastar.io/api/v2/"
    ;;
  full:check)
    kill_ports
    if docker info >/dev/null 2>&1; then
      cmd="docker:ensure"
      cd "$ROOT_DIR"
      if ! docker image inspect myexdraw-excalidraw:local >/dev/null 2>&1; then
        docker buildx build --platform linux/amd64 -t myexdraw-excalidraw:local --load "$EXCALIDRAW_DIR"
      fi
      docker compose up -d
      docker compose ps
    else
      echo "Docker daemon not available" >&2
      exit 1
    fi
    stop_tunnel
    start_tunnel
    curl_code "https://myexdraw.aastar.io/"
    curl_code "https://myexdraw.aastar.io/api/v2/"
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
