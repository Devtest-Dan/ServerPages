# ServerPages

Silent screen broadcaster + media file server accessible over the internet.

## What it does

- **Live screen stream** — captures your desktop via FFmpeg, playable in any browser
- **Two streaming modes** — HLS (standard, 4-10s latency) or WebSocket + fMP4 (low latency, ~0.5-1s)
- **Media file browser** — browse and play video, audio, and image files on C: and D: drives
- **Internet accessible** — free HTTPS URL via Tailscale Funnel, no port forwarding needed
- **Zero interaction** — starts on any user login, runs fully hidden (no console window, no tray icon), auto-restarts if killed

## Architecture

```
wscript.exe → node.exe (Express + WebSocket server on :3333, hidden window)
                ├── ffmpeg.exe (HLS mode: screen → .ts segments)
                └── ffmpeg.exe (WS mode: screen → fMP4 pipe → WebSocket broadcast)

Task Scheduler "ServerPages" → triggers on any user logon, restarts on failure
Tailscale service (unattended) → Funnel proxies :3333 to https://<machine>.ts.net
```

**2 visible processes in Task Manager:** `node.exe` + `ffmpeg.exe` (no console window)
**Tailscale:** runs as a Windows service — no GUI, no tray icon

## Pages

| URL | Description |
|---|---|
| `/` | Dashboard — live stream preview + media browser link |
| `/live.html` | Full live screen stream with mode toggle (HLS / Low Latency) and quality toggle (720p / 1080p) |
| `/media.html` | File browser + inline player (video/audio/image) + download |

## Streaming Modes

### HLS (default)
- FFmpeg outputs H.264 segments to `stream/` directory
- Browser loads `screen.m3u8` via HLS.js
- **Latency:** 4-10 seconds
- **Compatibility:** all browsers, all devices

### WebSocket + fMP4 (Low Latency)
- FFmpeg outputs fragmented MP4 to stdout (`pipe:1`)
- Server parses MP4 box headers, caches init segment (ftyp+moov) for late joiners
- Broadcasts media segments to all WebSocket clients on `/ws/stream`
- Browser uses MediaSource Extensions (MSE) API to decode and play
- Buffer management: keeps ~5s, trims old data automatically
- **Latency:** ~0.5-1 second
- **Compatibility:** all modern desktop browsers (Chrome, Edge, Firefox, Safari 17+)

### Mode switching
Switch modes via the **HLS | Low Latency** toggle on the live page, or via the API:
```bash
curl -X POST http://localhost:3333/api/mode -H 'Content-Type: application/json' -d '{"mode":"ws"}'
```
Switching restarts FFmpeg with the appropriate output format. Active WebSocket clients receive the init segment on connect for instant playback.

## API

| Method | Route | Description |
|---|---|---|
| GET | `/api/status` | Server status: FFmpeg running, stream ready, current mode, quality, WS client count |
| POST | `/api/mode` | Switch streaming mode: `{"mode":"hls"}` or `{"mode":"ws"}` |
| POST | `/api/quality` | Set quality: `{"quality":"720p"}` or `{"quality":"1080p"}` |
| GET | `/api/files?dir=C:/` | List directories + media files |
| GET | `/api/stream?path=...` | Stream file (Range support for seeking) |
| GET | `/api/download?path=...` | Download file |
| GET | `/hls/screen.m3u8` | Live HLS manifest (HLS mode only) |
| WS | `/ws/stream` | WebSocket binary stream (WS mode only) — receives init segment on connect, then fMP4 chunks |

### Status response example
```json
{
  "ffmpeg": true,
  "ffmpegPid": 12345,
  "uptime": 3600.5,
  "streamReady": true,
  "streamMode": "hls",
  "quality": "720p",
  "wsClients": 0
}
```

## Quality Presets

| Preset | Resolution | Bitrate | Max Rate | Buffer |
|---|---|---|---|---|
| 720p | 1280x720 | 2000k | 2500k | 5000k |
| 1080p | 1920x1080 | 4000k | 5000k | 10000k |

Both modes use: `libx264 -preset ultrafast -tune zerolatency -g 60 -pix_fmt yuv420p`
WS mode additionally uses: `-profile:v baseline -level 3.0` (for MSE codec compatibility)

## Supported Formats

- **Video:** mp4, mkv, avi, mov, wmv, flv, webm, m4v, mpg, mpeg, 3gp, 3g2, ts, mts, m2ts, vob, ogv, f4v, asf, rm, rmvb
- **Audio:** mp3, wav, flac, aac, ogg, wma, m4a, opus
- **Image:** jpg, jpeg, png, gif, bmp, webp, svg, ico, tiff, tif, heic, heif, avif

## Install

### New machine (one-click)

Save `install.bat` to the machine and double-click it. That's it.

It downloads the repo, installs Node.js, FFmpeg, Tailscale, configures Task Scheduler, enables Funnel, hides the tray icon, and starts the server. The only manual moment is the Tailscale login browser window (first time only).

### Existing machine (update)

```
setup.bat
```

Re-run to reconfigure Task Scheduler, Tailscale, and tray icon settings.

### What setup.bat does

1. Creates directories (`bin/`, `stream/`, `logs/`, `server/public/`)
2. Installs Node.js v22 LTS (if missing) — downloads MSI from nodejs.org
3. Downloads FFmpeg (if missing) — from github.com/BtbN/FFmpeg-Builds (~80MB)
4. Runs `npm install --production` in `server/`
5. Creates Task Scheduler entry "ServerPages" (any user logon, hidden, restart on failure every 1 min, up to 999 retries)
6. Installs + configures Tailscale (login, unattended mode, Funnel on port 3333)
7. Hides Tailscale tray icon (removes startup shortcut, kills GUI process)

### Internet URL

```
https://<machine-name>.tailXXXXX.ts.net
```

Replace `<machine-name>` with whatever Tailscale assigns to the machine.

### Manual start/stop

```
start.bat    # start in background (hidden via VBS launcher)
stop.bat     # graceful stop (flag file → wait → force kill)
```

After setup, everything auto-starts on any user login — fully hidden, no manual intervention needed.

## Auto-restart

| Scenario | Recovery |
|---|---|
| ffmpeg.exe killed | node.exe respawns it in 3 seconds |
| node.exe killed | Task Scheduler restarts it in ~1 minute |
| Both killed | Task Scheduler → node.exe → ffmpeg.exe |
| Reboot | Task Scheduler triggers on any user logon |

## Resource Usage

| Process | CPU (720p) | CPU (1080p) | RAM |
|---|---|---|---|
| Node.js | <1% | <1% | ~40MB |
| FFmpeg | 5-10% | 10-15% | ~50MB |

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `express` | ^4.21.0 | HTTP server, static files, REST API |
| `ws` | ^8.19.0 | WebSocket server for low-latency streaming |

No other runtime dependencies. FFmpeg is a standalone binary in `bin/`.

## Security

- File browser restricted to C:\ and D:\ drives only (`ALLOWED_ROOTS`)
- Only media file extensions are served (no exe, dll, etc.)
- Path traversal protection (`path.resolve` + allowlist check)
- No authentication (by design — Tailscale provides network-level access control)
- Tailscale URL is not publicly discoverable

## How the Live Stream Works

### Startup flow
1. Server starts → kills any orphaned ffmpeg.exe processes
2. Starts FFmpeg in current mode (HLS by default)
3. **HLS mode:** FFmpeg writes `.ts` segments + `screen.m3u8` to `stream/` directory
4. **WS mode:** FFmpeg writes fragmented MP4 to stdout pipe; server parses MP4 box headers to find the init segment (everything before the first `moof` box), caches it, then broadcasts all subsequent chunks to WebSocket clients

### Client connection flow
1. Page loads → calls `GET /api/status` first (never blindly loads HLS)
2. If FFmpeg not running → shows "FFmpeg not running" overlay
3. If FFmpeg running but stream not ready → shows "FFmpeg starting..." with spinner
4. If stream ready → connects in the appropriate mode:
   - **HLS:** loads `screen.m3u8` via HLS.js
   - **WS:** opens WebSocket to `/ws/stream`, creates `MediaSource`, appends chunks to `SourceBuffer`
5. Handles autoplay block → shows "Click to Play" button
6. On error/disconnect → exponential backoff retry (5s → 10s → 15s cap)

### Late-join (WS mode)
When a new WebSocket client connects, the server immediately sends the cached init segment (ftyp+moov). This allows the browser's MSE decoder to initialize without waiting for the next keyframe. The client then receives live media chunks and begins playback.

### Buffer management (WS mode)
- Client keeps ~5 seconds of buffered data
- Trims old data when buffer exceeds threshold
- Caps pending buffer queue at 30 chunks to prevent memory issues
- Drops oldest frames under backpressure

## Graceful Shutdown

The stop sequence (triggered by `stop.bat`, SIGTERM, SIGINT, or `stop.flag`):
1. Close all WebSocket clients
2. Send SIGTERM to FFmpeg
3. Clean HLS segments from `stream/`
4. Exit after 1 second

The `stop.flag` mechanism enables Windows-friendly shutdown without signals — a polling interval checks every 2 seconds.

## Logging

- Log file: `logs/serverpages.log`
- Auto-rotates at 5MB (keeps one `.old` backup)
- Logs: FFmpeg start/stop/errors, WebSocket connections, quality/mode changes, shutdown events
- FFmpeg frame progress (`frame=...`) lines are filtered out to reduce noise

## File Structure

```
D:\ServerPages\
  bin/
    ffmpeg.exe              ← downloaded by setup.bat (~130MB)
    launch-hidden.vbs       ← VBS wrapper to run node.exe with no console window
  deps/                     ← optional: pre-downloaded installers (node, tailscale, ffmpeg)
  stream/                   ← HLS segments (auto-cleaned on shutdown)
  logs/
    serverpages.log         ← app log (auto-rotated at 5MB)
  server/
    server.js               ← Express + WebSocket server, FFmpeg manager, REST API
    package.json            ← dependencies: express, ws
    public/
      index.html            ← Dashboard (stream preview + media browser link)
      live.html             ← Live stream player (HLS + MSE, mode/quality toggles)
      media.html            ← File browser + inline player + download
      style.css             ← Dark theme (CSS custom properties)
  install.bat               ← One-click installer (downloads repo, runs setup)
  setup.bat                 ← Full setup (Node.js, FFmpeg, Tailscale, Task Scheduler)
  start.bat                 ← Manual start (hidden via VBS)
  stop.bat                  ← Manual stop (flag → wait → force kill)
  stop.flag                 ← created by stop.bat, polled by server for shutdown
```

## Server Internals

### Key modules in `server.js`

| Function | Purpose |
|---|---|
| `startFfmpeg()` | Spawns FFmpeg in HLS mode (outputs to `stream/` directory) |
| `startFfmpegWs()` | Spawns FFmpeg in WS mode (fMP4 to stdout pipe, broadcasts to WebSocket clients) |
| `startCurrentMode()` | Delegates to the correct FFmpeg starter based on `streamMode` |
| `findBox(buf, type)` | Scans MP4 buffer for a box type (e.g., `moof`) by matching 4-byte type tag at offset +4 |
| `broadcast(data)` | Sends binary data to all connected WebSocket clients |
| `scheduleRestart()` | Restarts FFmpeg after 3 seconds if it dies unexpectedly |
| `killOrphanedFfmpeg()` | On startup, kills any leftover ffmpeg.exe processes from previous runs |
| `cleanStreamDir()` | Removes all files from `stream/` directory |
| `shutdown(signal)` | Graceful shutdown: closes WS clients, kills FFmpeg, cleans segments |

### State variables

| Variable | Type | Description |
|---|---|---|
| `streamMode` | `'hls'` \| `'ws'` | Current streaming mode |
| `ffmpegProcess` | `ChildProcess \| null` | Active FFmpeg process |
| `ffmpegRestarting` | `boolean` | Debounce flag for restart scheduling |
| `currentQuality` | `'720p'` \| `'1080p'` | Active quality preset |
| `wsClients` | `Set<WebSocket>` | Connected WebSocket clients |
| `initSegment` | `Buffer \| null` | Cached fMP4 init segment (ftyp+moov) for late joiners |
| `shuttingDown` | `boolean` | Prevents restarts during shutdown |
