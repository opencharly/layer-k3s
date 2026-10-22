# k3s

k3s binary installer and shared-containerd wiring for OpenCharly images.

The `k3s` candy downloads the k3s multi-call binary (sha256-verified against the
release manifest) to `/usr/local/bin/k3s` and symlinks `kubectl`, `crictl`, and
`ctr` onto it (k3s dispatches on `argv[0]`). It also installs the runtime
dependencies kube-proxy and the apiserver tunnel need — `iptables`, `conntrack`,
`socat`, `ethtool`, and `ca-certificates` — via the distro package manager, not
the upstream `curl | sh` installer.

The `k3s-shared-containerd` candy composes that binary and points k3s at the ONE
shared containerd instead of letting k3s start its embedded one.

Neither candy starts a service. Role selection happens in `k3s-server` and
`k3s-agent`, which wrap this binary with the right CLI verb.

## What it provides

| Property | `k3s` | `k3s-shared-containerd` |
|---|---|---|
| Binary | `/usr/local/bin/k3s` (symlinks: `kubectl`, `crictl`, `ctr`) | inherits `k3s` |
| Pinned version | `v1.37.0+k3s1` | inherits `k3s` |
| Packages | `ca-certificates`, `ethtool`, `fuse-overlayfs`, `socat` + per-distro `iptables`/`conntrack` | none of its own |
| Install files | `charly.yml` (`run:` step) | `charly.yml` (`write:` steps) |
| Service / port | none | none |
| Shared daemon | — | `/run/containerd/containerd.sock` (not started here) |

## How to use it

### The binary only

Typically not used directly — compose `/charly-infrastructure:k3s-server` or
`/charly-infrastructure:k3s-agent`, which depend on this candy. For a bare
binary-only image, pin this repo in a box's `candy:` list:

```yaml
k3s-base:
  candy:
    base: fedora
    candy:
      - '@github.com/opencharly/layer-k3s:v2026.293.0040'
```

### k3s on the shared containerd

Compose `k3s-shared-containerd` on a host image that already runs the rootful
shared daemon (`containerd-host`):

```yaml
k3s-shared:
  candy:
    base: cachyos
    candy:
      - k3s-shared-containerd
```

The layer installs:

- `/etc/rancher/k3s/config.yaml` with
  `container-runtime-endpoint: unix:///run/containerd/containerd.sock`. k3s then
  uses the shared image store and snapshotter; it starts no bundled containerd.
- `/etc/containerd/conf.d/50-k3s-cni.toml` — a **partial** containerd config
  carrying only the two k3s-specific CNI keys:
  `bin_dirs = ["/var/lib/rancher/k3s/data/current/bin"]` and
  `conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d"`. Without them pods
  start but have no network. The shared daemon's own config (`version = 4`,
  `imports = ["/etc/containerd/conf.d/*.toml"]`, the `crun`/`krun`/`nvidia`
  handlers) is owned by the containerd-host image, never by this layer.
- `/var/lib/rancher/k3s/server/manifests/krun-runtimeclass.yaml` and
  `nvidia-runtimeclass.yaml` — declarative `node.k8s.io/v1` RuntimeClasses
  (`handler: krun`, `handler: nvidia`). k3s auto-applies everything in that
  directory, so no imperative `kubectl apply` is needed. The handlers themselves
  live in the shared containerd's CRI config.

After the image is built:

```bash
/usr/local/bin/k3s --version     # k3s version v1.37.0+k3s1
/usr/local/bin/kubectl version --client
grep container-runtime-endpoint /etc/rancher/k3s/config.yaml
```

### The runtime set is read at start — restart k3s after a handler change

k3s asks the CRI for its runtime set (and cgroup driver) once, at start. A
handler added to the shared containerd later — for example the `nvidia` handler
written by the NVIDIA toolkit — is invisible to kubelet until `k3s` restarts.
The layer installs `/usr/local/bin/k3s-runtime-handler-guard`, which fingerprints
the merged containerd CRI runtime map and restarts k3s only when that
fingerprint moves. Its `run:` step executes at install time (recording the
baseline before k3s starts) and on every later application of the layer. If a
handler is added outside a charly run, restart k3s explicitly:

```bash
sudo systemctl restart k3s
```

## Test bed

`check-k3s-shared-containerd` is the three-step proof — absence, perform,
presence — of this layer on a **disposable containerd-host venue**:

1. `absent-before` — k3s is not running and no `krun` RuntimeClass is served.
2. `perform-start` — start k3s from the config this layer installed.
3. `present-after` — the node is Ready on `containerd://2.x`, k3s's pods are
   visible in `nerdctl -n k8s.io ps` on the SHARED socket (the proof it is not
   the embedded daemon), and both RuntimeClasses are served.

It is a `host: local` bed, so run it **inside** the disposable venue:

```bash
charly --host <containerd-host-vm> check run check-k3s-shared-containerd
```

Never run it on an operator workstation: the layer writes `/etc`, installs the
k3s binary, and starts a control plane.

## Layout

- `charly.yml` — the `k3s:` candy (verified binary install), the
  `k3s-shared-containerd:` candy (shared-containerd wiring), the
  `k3s-shared-containerd-app:` local template, the
  `check-k3s-shared-containerd:` bed, and the embedded `k3s-skill:` entity.
- `.agents/skills/k3s/SKILL.md` — the owning skill body.
- `.github/workflows/tag-on-merge.yml` — CalVer tag + `CHANGELOG/` on merge.
- `README.md` — this user overview.

## Related

- Owning skill: `/charly-infrastructure:k3s` — the binary installer and the
  shared-containerd contract
- Role candies: `/charly-infrastructure:k3s-server`, `/charly-infrastructure:k3s-agent`
- Canonical contracts: `K3S.md` §1, §2, §4, §5 and `CONTAINERD-IMAGES.md` §1.7
  in the [`opencharly/opencharly`](https://github.com/opencharly/opencharly) umbrella
- Operator tooling: `/charly-coder:kubernetes-layer` (distro `kubectl`/`helm`)
- Cluster probe verb: `/charly-kubernetes:check-k8s`
- [`opencharly/charly`](https://github.com/opencharly/charly) — the charly CLI and image builder
