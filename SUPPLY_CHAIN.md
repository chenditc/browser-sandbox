# Supply Chain Documentation

This document describes every external dependency in the `browser-sandbox` container image, why it was chosen, what alternatives were considered, and what integrity measures are in place.

## Origin

This image is a slim rebuild of [`ghcr.io/agent-infra/sandbox`](https://github.com/agent-infra/sandbox) (aio-sandbox), which bundles ~15 services into a 6 GB image. We stripped it down to 3 core features:

1. **Chrome browser** running with a virtual display
2. **CDP (Chrome DevTools Protocol) API** for programmatic browser control
3. **Web VNC** for visual observation of the browser

The result is a ~1.1 GB image with 5 processes instead of 15+.

---

## Dependencies

### 1. Base Image: Ubuntu 24.04 LTS

| | |
|---|---|
| **Source** | `ubuntu@sha256:cd1dba651b3080c3686ecf4e3c4220f026b521fb76978881737d24f200828b2b` |
| **Publisher** | Canonical (official Docker Hub image) |
| **Integrity** | Pinned by SHA256 digest, not floating tag |
| **Trust level** | High — official, widely audited |

**Why Ubuntu 24.04?** Initially built on 22.04, but upgraded to 24.04 for newer security patches and package versions. Required fixing three package renames (`libasound2` → `libasound2t64`, `libatk-bridge2.0-0` → `libatk-bridge2.0-0t64`, `libgtk-3-0` → `libgtk-3-0t64`) and removing the default `ubuntu` user (uid/gid 1000 conflict).

### 2. System Packages (apt)

| Package | Purpose |
|---------|---------|
| `supervisor` | Process manager (runs all services) |
| `nginx` | Reverse proxy — single port for CDP, VNC, health check |
| `tigervnc-standalone-server` | Virtual X display (Xvnc) + VNC server |
| `openbox` | Minimal window manager (Chrome runs maximized, no decorations) |
| `fonts-liberation`, `fonts-noto-cjk` | Fonts for web rendering (Latin + CJK) |
| `libgtk-3-0t64`, `libnss3`, `libgbm1`, etc. | Chrome runtime dependencies |

| | |
|---|---|
| **Source** | Ubuntu apt repositories (`archive.ubuntu.com`, `security.ubuntu.com`) |
| **Publisher** | Canonical |
| **Integrity** | GPG-signed package repository |
| **Trust level** | High |

### 3. Google Chrome Stable

| | |
|---|---|
| **Source** | `https://dl.google.com/linux/chrome/deb/` |
| **Publisher** | Google |
| **Integrity** | GPG key verified (`linux_signing_key.pub` → keyring), apt package signatures |
| **Trust level** | High |
| **Pinning** | Not version-pinned (installs latest stable). Consider pinning for reproducibility. |

**Why Google Chrome (not Chromium)?** The upstream aio-sandbox uses Playwright's Chromium build, which is downloaded as an unverified binary. Google Chrome stable is installed from Google's official GPG-signed apt repository — a stronger supply chain. It is also the most widely used browser, ensuring maximum web compatibility.

### 4. websocat v1.13.0

| | |
|---|---|
| **Source** | `https://github.com/vi/websocat/releases/download/v1.13.0/websocat.x86_64-unknown-linux-musl` |
| **Publisher** | [vi/websocat](https://github.com/vi/websocat) (Vitaly Shukela) |
| **Integrity** | SHA256 checksum verified at build time: `8f84c57103d33ab73888707041765e0e7e6a43a91fbb6e1828cd5eabc19ae32c` |
| **Trust level** | Medium — individual maintainer, pre-built binary, but checksum-pinned |
| **Binary type** | Static musl binary (~6 MB), zero runtime dependencies |

**What it does:** Bridges WebSocket connections to raw TCP. noVNC (browser-based VNC client) speaks WebSocket, but TigerVNC's Xvnc only speaks raw TCP/VNC protocol. websocat sits between them.

**Why websocat is necessary (alternatives considered):**

| Alternative | Outcome |
|---|---|
| **TigerVNC native WebSocket** | Investigated. TigerVNC 1.13.1 (latest in Ubuntu 24.04) has no WebSocket support. The [feature request](https://github.com/TigerVNC/tigervnc/issues/1768) is still open with no implementation. Not viable. |
| **websockify (apt package)** | Available in Ubuntu repos (`apt install websockify`), GPG-signed. However, it pulls in Python3 + numpy + jwcrypto — 13 additional packages (~70 MB). Significant bloat for a simple WebSocket-to-TCP bridge. |
| **websocat (current choice)** | Single 6 MB static binary, no runtime dependencies. Lower trust (GitHub release from individual maintainer) but mitigated by SHA256 checksum pinning. Best size/trust tradeoff. |

### 5. noVNC v1.4.0

| | |
|---|---|
| **Source** | `https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz` |
| **Publisher** | [novnc/noVNC](https://github.com/novnc/noVNC) (official project) |
| **Integrity** | SHA256 checksum verified at build time: `89b0354c94ad0b0c88092ec7a08e28086d3ed572f13660bac28d5470faaae9c1` |
| **Trust level** | High — well-known open-source project, pure HTML/JS (no server-side execution) |
| **Risk** | Low — served as static files by nginx, runs only in the user's browser |

**What it does:** Web-based VNC client. Served as static HTML/JS at `/vnc/`, connects to websocat's WebSocket endpoint to display the virtual desktop.

---

## CDP API: nginx vs gem-server

The upstream aio-sandbox uses `gem-server`, a FastAPI Python application that proxies Chrome's CDP endpoints and rewrites WebSocket URLs so remote clients can connect.

**We replaced it with pure nginx `sub_filter` rewriting:**

| Approach | Pros | Cons |
|---|---|---|
| **gem-server (upstream)** | Robust URL rewriting, custom CDP commands, logging control | Requires Python3 + pip + FastAPI + uvicorn + httpx + websockets (~100 MB) |
| **nginx sub_filter (our choice)** | Zero additional dependencies, pure config | Requires careful `Host` header handling (see below) |

**Key implementation detail:** Chrome uses the incoming `Host` header to construct WebSocket URLs in its `/json` responses. We set `proxy_set_header Host "127.0.0.1:9222"` so Chrome includes the port in its response (`ws://127.0.0.1:9222/devtools/...`). nginx's `sub_filter` then rewrites this to `$ws_scheme://$original_host`, where `$original_host` captures the caller's actual host before the proxy modifies it.

---

## Architecture

```
Port 8080 (nginx)
├── /v1/ping          → 200 "pong" (health check)
├── /json, /json/*    → Chrome CDP :9222 (with URL rewriting)
├── /devtools/*       → Chrome CDP :9222 (WebSocket proxy)
├── /vnc/             → noVNC static files
└── /ws, /websockify  → websocat :6080 → Xvnc :5900
```

5 processes managed by supervisord:
1. **Xvnc** (TigerVNC) — virtual X display + VNC server on `:99`
2. **openbox** — window manager (Chrome maximized, no decorations)
3. **google-chrome-stable** — browser with `--remote-debugging-port=9222`
4. **websocat** — WebSocket (port 6080) ↔ TCP (port 5900) bridge
5. **nginx** — reverse proxy on port 8080

---

## Hardening Measures

1. **Base image pinned by digest** — reproducible builds, immune to tag mutation
2. **websocat SHA256 verified** — build fails if binary doesn't match expected hash
3. **noVNC SHA256 verified** — build fails if tarball doesn't match expected hash
4. **Chrome from GPG-signed apt repo** — package signatures verified by apt
5. **System packages from Canonical repos** — GPG-signed, widely audited
6. **No Python runtime** — eliminated the entire Python stack (upstream had FastAPI + pip dependencies)
7. **Minimal attack surface** — only 5 processes vs 15+ in upstream

## Remaining Considerations

- **Chrome is not version-pinned** — `google-chrome-stable` installs whatever the latest version is. Pin with `google-chrome-stable=<version>` for fully reproducible builds.
- **websocat is from an individual maintainer** — mitigated by checksum pinning, but monitor for project health. If the project becomes unmaintained, switch to `websockify` from apt (accepting the Python dependency).
