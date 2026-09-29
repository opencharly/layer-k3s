# k3s

k3s binary installer layer for OpenCharly images.

The `k3s` candy downloads the k3s multi-call binary (sha256-verified against the
release manifest) to `/usr/local/bin/k3s` and symlinks `kubectl`, `crictl`, and
`ctr` onto it (k3s dispatches on `argv[0]`). It also installs the runtime
dependencies kube-proxy and the apiserver tunnel need — `iptables`, `conntrack`,
`socat`, `ethtool`, and `ca-certificates` — via the distro package manager, not
the upstream `curl | sh` installer.

No service is started here. Role selection happens in `k3s-server` and
`k3s-agent`, which wrap this binary with the right CLI verb.

## What it provides

| Property | Value |
|---|---|
| Layer / candy | `k3s` |
| Binary | `/usr/local/bin/k3s` (symlinks: `kubectl`, `crictl`, `ctr`) |
| Pinned version | `v1.31.11+k3s1` |
| Packages | `ca-certificates`, `ethtool`, `fuse-overlayfs`, `socat` + per-distro `iptables`/`conntrack` |
| Install files | `charly.yml` (`run:` step) |
| Service / port | none |

## How to use it

Typically not used directly — compose `/charly-infrastructure:k3s-server` or
`/charly-infrastructure:k3s-agent`, which depend on this candy. For a bare
binary-only image, pin this repo in a box's `candy:` list:

```yaml
k3s-base:
  candy:
    base: fedora
    candy:
      - '@github.com/opencharly/layer-k3s:v2026.239.1630'
```

After the image is built:

```bash
/usr/local/bin/k3s --version     # k3s version v1.31.11+k3s1
/usr/local/bin/kubectl version --client
```

## Layout

- `charly.yml` — the `k3s:` candy entity: the `package:`/`distro:` sections, the
  checksum-verified `run:` install step, the `check:` assertions, and the
  embedded `skill:` entity.
- `.github/workflows/tag-on-merge.yml` — CalVer tag + `CHANGELOG/` on merge.
- `README.md` — this user overview.

## Related

- Owning skill: `/charly-infrastructure:k3s` — the k3s binary installer
- Role candies: `/charly-infrastructure:k3s-server`, `/charly-infrastructure:k3s-agent`
- Operator tooling: `/charly-coder:kubernetes-layer` (distro `kubectl`/`helm`)
- Cluster probe verb: `/charly-kubernetes:check-k8s`
- [`opencharly/charly`](https://github.com/opencharly/charly) — the charly CLI and image builder
- [`opencharly/opencharly`](https://github.com/opencharly/opencharly) — the umbrella
