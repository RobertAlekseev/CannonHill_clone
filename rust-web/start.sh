#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
mode=${1:---offline}
port=${2:-8000}
case "$mode" in --lan|--offline|--build-only) ;; *) echo 'Usage: sh rust-web/start.sh [--lan|--offline|--build-only] [port]' >&2; exit 2 ;; esac

cargo build --locked --target-dir target --release --target wasm32-unknown-unknown
mkdir -p dist
cp index.html app.js target/wasm32-unknown-unknown/release/cannon_hill_web.wasm dist/
case "$mode" in
    --lan) exec cargo run --locked --target-dir target --release --features lan --bin cannon-hill-lan -- "0.0.0.0:$port" dist ;;
    --offline) exec python3 -m http.server "$port" --bind 127.0.0.1 --directory dist ;;
esac
