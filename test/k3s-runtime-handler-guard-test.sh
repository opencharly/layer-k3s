#!/bin/bash
# Branch regression test for files/k3s-runtime-handler-guard.sh.
#
# Exercises every path the installed guard can take, with stubbed systemctl and
# containerd and a private unix socket. Nothing on the host is restarted and the
# host's /run/containerd is never touched.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="$root/files/k3s-runtime-handler-guard.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state"
socket="$tmp/containerd.sock"
python3 - "$socket" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.close()
PY

cat > "$tmp/bin/systemctl" <<EOF
#!/bin/sh
case "\$1" in
  is-active) [ -f "$tmp/active" ] && exit 0 || exit 3 ;;
  restart) echo restart >> "$tmp/restarts"; exit 0 ;;
esac
exit 1
EOF
cat > "$tmp/bin/containerd" <<EOF
#!/bin/sh
cat "$tmp/dump.toml"
EOF
chmod +x "$tmp/bin/systemctl" "$tmp/bin/containerd"

one_handler() {
    cat > "$tmp/dump.toml" <<'EOF'
      [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes]
        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
          runtime_type = 'io.containerd.runc.v2'
EOF
}
two_handlers() {
    cat > "$tmp/dump.toml" <<'EOF'
      [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes]
        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
          runtime_type = 'io.containerd.runc.v2'
        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.krun]
          runtime_type = 'io.containerd.runc.v2'
EOF
}

run_guard() {
    PATH="$tmp/bin:$PATH" \
    K3S_HANDLER_GUARD_STATE_DIR="$tmp/state" \
    K3S_HANDLER_GUARD_SOCKET="$socket" \
    sh "$guard"
}
restarts() { if [ -f "$tmp/restarts" ]; then wc -l < "$tmp/restarts" | tr -d ' '; else echo 0; fi; }
expect_restarts() {
    local want="$1" got
    got="$(restarts)"
    [ "$got" -eq "$want" ] || { echo "FAIL: expected $want restarts, got $got"; exit 1; }
}
state_value() { cat "$tmp/state/runtime-handlers.sha256" 2>/dev/null || echo absent; }

one_handler
rm -f "$tmp/active" "$tmp/restarts"
rm -rf "$tmp/state"; mkdir -p "$tmp/state"

# 0. No shared-daemon socket: no baseline, no restart.
mv "$socket" "$socket.off"
run_guard
expect_restarts 0
[ "$(state_value)" = absent ] || { echo "FAIL: a baseline was written without a socket"; exit 1; }
mv "$socket.off" "$socket"

# 1. Socket, one handler, k3s inactive: baseline recorded, no restart.
run_guard
expect_restarts 0
[ -s "$tmp/state/runtime-handlers.sha256" ] || { echo "FAIL: no baseline with a socket"; exit 1; }
first="$(state_value)"

# 2. Unchanged set, k3s active: no restart.
touch "$tmp/active"
run_guard
expect_restarts 0
[ "$(state_value)" = "$first" ] || { echo "FAIL: unchanged fingerprint moved"; exit 1; }

# 3. Handler added while k3s runs: one restart, new fingerprint.
two_handlers
run_guard
expect_restarts 1
[ "$(state_value)" != "$first" ] || { echo "FAIL: changed fingerprint was not recorded"; exit 1; }

# 4. Unchanged again: no restart.
run_guard
expect_restarts 1

# 5. Set changed while k3s is inactive: baseline updates, no restart.
one_handler
rm -f "$tmp/active"
run_guard
expect_restarts 1
[ "$(state_value)" = "$first" ] || { echo "FAIL: inactive-change baseline not updated"; exit 1; }

# 6. First run while k3s is already active: baseline + exactly one restart.
rm -rf "$tmp/state"; mkdir -p "$tmp/state"
touch "$tmp/active"
run_guard
expect_restarts 2
[ -s "$tmp/state/runtime-handlers.sha256" ] || { echo "FAIL: no baseline on the first active run"; exit 1; }

echo "PASS: 7 guard scenarios (0-6)"
