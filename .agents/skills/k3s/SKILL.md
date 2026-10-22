---
name: k3s
description: 'k3s binary installer (common base for k3s-server and k3s-agent) and
  the shared-containerd wiring (k3s-shared-containerd).

  Use when building images that need the k3s binary, and when pointing k3s at the
  ONE shared containerd with the krun/nvidia RuntimeClasses and the
  restart-after-runtime-handler-change rule.'
---

# k3s -- k3s binary installer (base layer)

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (binary fetch + symlinks via a `run:` plan step) |
| Pinned version | `v1.37.0+k3s1` (edit `K3S_VERSION` in `charly.yml` vars to cut over) |

## What this candy does

Downloads the verified-checksum k3s binary (plus sha256sum from the
release manifest), installs it to `/usr/local/bin/k3s`, and creates
symlinks for `kubectl`, `crictl`, `ctr` (k3s is multi-call). Installs
runtime dependencies (`iptables`, `conntrack`, `socat`, `ethtool`,
`ca-certificates`) via the distro package manager — **not** via the
upstream `curl | sh` installer. Deliberate, per R9.

**No service is started by this candy.** Role selection happens in the
dependent candies `/charly-infrastructure:k3s-server` and `/charly-infrastructure:k3s-agent`,
which emit systemd units that wrap this binary with the right CLI verb
(`k3s server` vs `k3s agent`).

## Usage

Typically not used directly — compose `/charly-infrastructure:k3s-server` or
`/charly-infrastructure:k3s-agent` (both depend on this candy).

```yaml
# For a bare binary-only image (rare) — a box composes the candy via an
# inline candy: list in its body:
k3s-base:
  candy:
    base: fedora
    candy:
      - k3s
```

## k3s-shared-containerd — k3s on the ONE shared containerd

`k3s-shared-containerd` composes the `k3s` candy and points k3s at the shared
rootful daemon (`K3S.md` §1, §2, §4; `CONTAINERD-IMAGES.md` §1.7). It starts no
daemon and owns no part of the shared containerd's config.

| Artifact | Value |
|---|---|
| k3s config | `/etc/rancher/k3s/config.yaml` → `container-runtime-endpoint: unix:///run/containerd/containerd.sock` |
| CNI drop-in | `/etc/containerd/conf.d/50-k3s-cni.toml` (partial): `bin_dirs = ["/var/lib/rancher/k3s/data/current/bin"]`, `conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d"` |
| RuntimeClasses | `/var/lib/rancher/k3s/server/manifests/{krun,nvidia}-runtimeclass.yaml` (`node.k8s.io/v1`, `handler: krun` / `handler: nvidia`) |
| Handler guard | `/usr/local/bin/k3s-runtime-handler-guard` + a `run:` step that records the baseline and restarts k3s only when the handler set moved |
| Service / port | none (k3s-server / the lease image owns the unit) |

**Namespaces.** k3s uses `k8s.io`; nerdctl uses `default`, on the same socket.

**The CNI drop-in is required.** k3s writes its flannel conflist and CNI binaries
under `/var/lib/rancher/k3s`; stock containerd does not read them. Without the two
keys, pods start but have no network. The drop-in is a PARTIAL config: it adds
only these keys to the shared daemon's `version = 4` config, which imports
`/etc/containerd/conf.d/*.toml`. Never rewrite the shared daemon's full config
from this layer.

**The restart-after-handler-change rule.** k3s reads the CRI runtime set (and the
cgroup driver) once, at start; a handler added later is invisible to kubelet until
`k3s` restarts (`K3S.md` §2.3 step 3). The guard fingerprints the MERGED containerd
runtime map (`containerd config dump`, which includes `conf.d`) and restarts k3s
only when the fingerprint changes:

- fresh deploy: the layer's `run:` step records the baseline before k3s starts;
- later layer application: the step compares and restarts on a change;
- a handler added outside charly: run `sudo systemctl restart k3s` (or the guard
  script) explicitly.

The guard exits 0 when k3s is not active, which is what makes the same `run:` step
safe at image-build time and on a venue that has not started k3s yet.

**The discriminating proof.** `nerdctl -n k8s.io ps` on
`/run/containerd/containerd.sock` must show k3s's pods. An embedded containerd
would hold them on its own socket, leaving that namespace empty.

**Bed.** `check-k3s-shared-containerd` is the absence → perform → presence proof.
It is a `host: local` bed and must run inside a disposable containerd-host venue
(`charly --host <containerd-host-vm> check run check-k3s-shared-containerd`),
never on an operator workstation.

## Cross-distro coverage

- `rpm:` (Fedora) — `conntrack-tools`, `iptables`, `ethtool`, `socat`, `ca-certificates`
- `pac:` (Arch) — `conntrack-tools`, `iptables-nft`, `ethtool`, `socat`, `ca-certificates`
- `deb:` (Debian/Ubuntu) — `conntrack`, `iptables`, `ethtool`, `socat`, `ca-certificates`

## Tests

- `k3s --version` matches pinned version.
- `/usr/local/bin/k3s` is mode 0755.
- `/usr/local/bin/kubectl` exists as a symlink.
- Each runtime package is installed (per-distro `package_map` handles Debian's `conntrack` rename).
- `k3s-shared-containerd`: the endpoint, both CNI keys, both RuntimeClass
  manifests, and the executable guard are present.
- The bed proves an absence, then a Ready node on the shared containerd with
  k3s's pods in `nerdctl -n k8s.io ps`, then both RuntimeClasses.

## Related Candies
- `/charly-infrastructure:k3s-server` — Control-plane node (depends on this candy)
- `/charly-infrastructure:k3s-agent` — Worker node (depends on this candy)
- `/charly-coder:kubernetes-layer` — Distro `kubectl`/`helm` binaries for the operator, not the cluster
