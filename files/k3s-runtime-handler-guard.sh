#!/bin/sh
# Restart k3s when the shared containerd's runtime-handler set changed.
#
# k3s asks the CRI for its runtime set (and cgroup driver) once, at start, and
# latches the answer. A handler added to the shared containerd afterwards is
# invisible to kubelet until the service restarts (K3S.md §2.3 step 3). This
# guard fingerprints the merged containerd CRI runtime map and restarts k3s
# only when that fingerprint moves while k3s is running.
set -eu

state_dir="${K3S_HANDLER_GUARD_STATE_DIR:-/var/lib/k3s-shared-containerd}"
state_file="${state_dir}/runtime-handlers.sha256"
socket_path="${K3S_HANDLER_GUARD_SOCKET:-/run/containerd/containerd.sock}"

# No shared daemon on this venue (image build, or a host that has not started
# it): there is no handler set to fingerprint and nothing to restart.
if [ ! -S "${socket_path}" ]; then
    exit 0
fi

if ! command -v containerd >/dev/null 2>&1; then
    echo "k3s-runtime-handler-guard: containerd is not on PATH; cannot read the runtime set" >&2
    exit 1
fi

# `containerd config dump` is the MERGED config: it includes conf.d drop-ins.
handlers="$(containerd config dump 2>/dev/null \
    | sed -n "s/^[[:space:]]*\[plugins\.[^]]*containerd\.runtimes\.\([^].]*\)\]$/\1/p" \
    | sort -u \
    | tr '\n' ' ')"

if [ -z "${handlers}" ]; then
    echo "k3s-runtime-handler-guard: the merged containerd config declares no CRI runtime handlers" >&2
    exit 1
fi

fingerprint="$(printf '%s' "${handlers}" | sha256sum | cut -d' ' -f1)"
mkdir -p "${state_dir}"

if [ ! -f "${state_file}" ]; then
    # Always record the baseline. The install step runs before k3s starts, so
    # this is the set the server will latch at its own start. If k3s was
    # already running when this layer arrived, its latch predates the baseline:
    # restart once so the running k3s actually sees the new set.
    printf '%s\n' "${fingerprint}" > "${state_file}"
    if systemctl is-active --quiet k3s 2>/dev/null; then
        echo "k3s-runtime-handler-guard: baseline recorded on a running k3s; restarting it" >&2
        systemctl restart k3s
    fi
    exit 0
fi

previous="$(cat "${state_file}")"
if [ "${previous}" = "${fingerprint}" ]; then
    exit 0
fi

printf '%s\n' "${fingerprint}" > "${state_file}"
if systemctl is-active --quiet k3s 2>/dev/null; then
    echo "k3s-runtime-handler-guard: runtime handlers changed; restarting k3s" >&2
    systemctl restart k3s
else
    echo "k3s-runtime-handler-guard: runtime handlers changed while k3s was not running; the next start will latch them" >&2
fi
