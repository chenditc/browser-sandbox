# browser-sandbox

A lightweight Docker container running Google Chrome with three interfaces:

- **CDP API** — Chrome DevTools Protocol for programmatic browser control
- **Web VNC** — Browser-based VNC viewer (noVNC) to observe the browser visually
- **Health Check** — `/v1/ping` endpoint for container orchestration

~1.1 GB image size, down from ~6 GB upstream ([aio-sandbox](https://github.com/agent-infra/aio-sandbox)).

## Quick Start

```bash
docker run -d --name browser-sandbox \
  --shm-size=2g \
  -p 8080:8080 \
  chenditc/browser-sandbox:latest
```

Or with docker-compose:

```bash
docker compose up -d
```

## Endpoints

All endpoints are served through a single port (default `8080`):

| Path | Description |
|------|-------------|
| `/` | Redirects to `/readme` |
| `/readme` | Quick usage page with endpoint links + README link |
| `/v1/ping` | Health check — returns `pong` |
| `/json` | CDP endpoint list with WebSocket URLs |
| `/json/version` | Chrome/CDP version info |
| `/devtools/page/<id>` | CDP WebSocket connection for a specific page |
| `/vnc/` | noVNC web viewer (trailing slash required) |

## Usage

### CDP (Chrome DevTools Protocol)

Get the CDP WebSocket URL:

```bash
curl http://localhost:8080/json
```

Response (URLs are automatically rewritten to match your host):

```json
[{
  "webSocketDebuggerUrl": "ws://localhost:8080/devtools/page/ABC123..."
}]
```

Connect with Playwright:

```python
from playwright.async_api import async_playwright

async with async_playwright() as p:
    # Get the WebSocket URL
    import httpx
    resp = httpx.get("http://localhost:8080/json/version")
    ws_url = resp.json()["webSocketDebuggerUrl"]

    # Connect to the running browser
    browser = await p.chromium.connect_over_cdp(ws_url)
    page = browser.contexts[0].pages[0]
    await page.goto("https://example.com")
```

Connect with Puppeteer:

```javascript
const puppeteer = require('puppeteer-core');

const resp = await fetch('http://localhost:8080/json/version');
const { webSocketDebuggerUrl } = await resp.json();

const browser = await puppeteer.connect({
  browserWSEndpoint: webSocketDebuggerUrl,
});
const [page] = await browser.pages();
await page.goto('https://example.com');
```

### Web VNC

Open `http://localhost:8080/vnc/` in a browser to see the Chrome window in real time. Useful for debugging automation scripts or visual verification.

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DISPLAY_WIDTH` | `1280` | Browser viewport width |
| `DISPLAY_HEIGHT` | `1024` | Browser viewport height |
| `DISPLAY_DEPTH` | `24` | Color depth |
| `TZ` | `UTC` | Timezone |
| `BROWSER_EXTRA_ARGS` | _(empty)_ | Additional Chrome command-line flags |

Example with custom resolution:

```bash
docker run -d --name browser-sandbox \
  --shm-size=2g \
  -p 8080:8080 \
  -e DISPLAY_WIDTH=1920 \
  -e DISPLAY_HEIGHT=1080 \
  chenditc/browser-sandbox:latest
```

## Architecture

Five processes managed by supervisord, all behind a single nginx reverse proxy on port 8080:

```
Port 8080 (nginx)
├── /json, /devtools/*  →  Chrome CDP (:9222)
├── /vnc/*              →  noVNC static files
├── /ws, /websockify    →  websocat (:6080) → Xvnc (:5900)
└── /v1/ping            →  nginx (direct response)

Supervisord
├── Xvnc (TigerVNC)    — Virtual X display + VNC server
├── openbox             — Window manager (Chrome maximized)
├── google-chrome       — Browser with CDP enabled
├── websocat            — WebSocket-to-TCP bridge for VNC
└── nginx               — Reverse proxy
```

## Supply Chain Security

All external dependencies are integrity-verified:

- **Base image**: Ubuntu 24.04 LTS pinned by SHA256 digest
- **System packages**: From Canonical's GPG-signed apt repos
- **Google Chrome**: From Google's GPG-signed apt repository
- **websocat v1.13.0**: SHA256 checksum verified at build time
- **noVNC v1.4.0**: SHA256 checksum verified at build time

See [SUPPLY_CHAIN.md](SUPPLY_CHAIN.md) for full details and design decisions.

## Building

```bash
docker build -t browser-sandbox .
```

## License

MIT
