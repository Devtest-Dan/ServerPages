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
                ├── ffmpeg.exe (HLS mode: screen → .ts segments → /hls/ static)
                └── ffmpeg.exe (WS mode: screen → fMP4 pipe:1 → box parser → WebSocket broadcast)

Task Scheduler "ServerPages" → triggers on any user logon, restarts on failure
Tailscale service (unattended) → Funnel proxies :3333 to https://<machine>.ts.net
```

**2 visible processes in Task Manager:** `node.exe` + `ffmpeg.exe` (no console window)
**Tailscale:** runs as a Windows service — no GUI, no tray icon

## Pages

| URL | Description |
|---|---|
| `/` | Dashboard — live stream preview (HLS) or mode label (WS) + media browser card |
| `/live.html` | Full live stream player with mode toggle (HLS / Low Latency) and quality toggle (720p / 1080p) |
| `/media.html` | File browser with breadcrumb nav + inline player (video/audio/image) + download |

## Streaming Modes

### HLS (default)

- FFmpeg captures desktop via `gdigrab`, encodes H.264, outputs `.ts` segments + `screen.m3u8` to `stream/` directory
- Browser loads manifest via HLS.js (`/hls/screen.m3u8`)
- Segments: 2 seconds each, rolling window of 5, old segments auto-deleted
- **Latency:** 4-10 seconds
- **Compatibility:** all browsers, all devices
- **FFmpeg flags:** `-g 60 -keyint_min 60` (2s GOP), `-f hls -hls_time 2 -hls_list_size 5`

### WebSocket + fMP4 (Low Latency)

- FFmpeg outputs fragmented MP4 to stdout (`pipe:1`) with `empty_moov` + `frag_keyframe` + `default_base_moof`
- Server accumulates pipe data in a buffer, parses MP4 box headers (4-byte size + 4-byte type), and only forwards **complete boxes**
- Init segment (ftyp + moov boxes, ~774 bytes) is cached for late-joining clients
- Media boxes (moof + mdat) are broadcast to all connected WebSocket clients
- Browser creates a `MediaSource` with `SourceBuffer` in **`sequence` mode** (ignores FFmpeg's wall-clock timestamps, generates sequential timestamps from 0)
- Player auto-seeks to the live edge whenever it falls >2 seconds behind the buffer
- **Latency:** ~0.5-1 second
- **Compatibility:** all modern desktop browsers (Chrome, Edge, Firefox, Safari 17+)
- **FFmpeg flags:** `-g 30 -keyint_min 30` (1s GOP), `-frag_duration 1000000` (1s fragments), `-f mp4 -movflags frag_keyframe+empty_moov+default_base_moof pipe:1`
- **MSE codec:** `avc1.42C01F` (Constrained Baseline Profile, Level 3.1 — auto-selected by libx264 with `ultrafast` + `zerolatency`)

### Why `sequence` mode + live edge seeking?

FFmpeg embeds wall-clock timestamps in fMP4 fragments (e.g., `baseMediaDecodeTime` = 1772630433). In MSE's default `segments` mode, these huge timestamps cause the buffer to be placed far ahead of `currentTime=0`, making the video unable to play. `sequence` mode remaps timestamps sequentially from 0, and live edge seeking ensures the player stays current even if timestamp gaps occur between fragments.

### Why complete box buffering?

FFmpeg's `pipe:1` delivers data in arbitrary chunks (whatever size the OS pipe buffer gives). These chunks can split MP4 boxes mid-way (e.g., half a `moof` header). MSE's SourceBuffer can parse partial data in theory, but in practice sending half-boxes causes decode errors and `HTMLMediaElement.error`. The server-side box parser reads the 4-byte big-endian size field, waits until the full box is accumulated, then sends only complete boxes over WebSocket.

### Mode switching

Switch modes via the **HLS | Low Latency** toggle on the live page, or via the API:
```bash
curl -X POST http://localhost:3333/api/mode -H 'Content-Type: application/json' -d '{"mode":"ws"}'
```
Switching kills the current FFmpeg process, which triggers `scheduleRestart()` after 3 seconds in the new mode. The client immediately tears down the current player (HLS.js or MediaSource), shows a "Switching..." overlay, and reconnects after the restart delay.

## API

| Method | Route | Description |
|---|---|---|
| GET | `/api/status` | Server status: FFmpeg running, stream ready, current mode, quality, WS client count |
| POST | `/api/mode` | Switch streaming mode: `{"mode":"hls"}` or `{"mode":"ws"}`. Restarts FFmpeg. |
| POST | `/api/quality` | Set quality: `{"quality":"720p"}` or `{"quality":"1080p"}`. Restarts FFmpeg. |
| GET | `/api/files?dir=C:/` | List directories + media files in given path |
| GET | `/api/stream?path=...` | Stream media file with HTTP Range support for seeking |
| GET | `/api/download?path=...` | Download media file as attachment |
| GET | `/hls/screen.m3u8` | Live HLS manifest (HLS mode only) |
| WS | `/ws/stream` | WebSocket binary stream (WS mode only) — receives init segment on connect, then complete fMP4 boxes |

### Status response

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

- `streamReady` checks `screen.m3u8` exists (HLS) or `initSegment !== null` (WS)
- `wsClients` is the count of currently connected WebSocket viewers

## Quality Presets

| Preset | Resolution | Bitrate | Max Rate | Buffer Size |
|---|---|---|---|---|
| 720p | 1280x720 | 2000k | 2500k | 5000k |
| 1080p | 1920x1080 | 4000k | 5000k | 10000k |

Both modes use: `libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p`

FFmpeg auto-selects H.264 level based on resolution (level 3.1 for 720p, level 4.0+ for 1080p). No manual `-profile` or `-level` is set — `ultrafast` + `zerolatency` naturally produces Constrained Baseline Profile (CABAC disabled).

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
| ffmpeg.exe killed | node.exe respawns it in 3 seconds via `scheduleRestart()` |
| node.exe killed | Task Scheduler restarts it in ~1 minute |
| Both killed | Task Scheduler → node.exe → ffmpeg.exe |
| Reboot | Task Scheduler triggers on any user logon |
| FFmpeg crash loop | `ffmpegRestarting` flag debounces to prevent rapid restarts |

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

### Server startup flow

1. `killOrphanedFfmpeg()` — finds and kills any leftover ffmpeg.exe from previous runs
2. Creates HTTP server (Express) + WebSocket server (`ws`) on port 3333
3. Calls `startCurrentMode()` which delegates to `startFfmpeg()` or `startFfmpegWs()` based on `streamMode`

### HLS mode pipeline

```
gdigrab (desktop) → libx264 (ultrafast/zerolatency) → HLS muxer
                                                         ├── seg000.ts, seg001.ts, ...
                                                         └── screen.m3u8
Browser: HLS.js loads screen.m3u8 → fetches .ts segments → decodes → plays
```

### WS mode pipeline

```
gdigrab (desktop) → libx264 (ultrafast/zerolatency) → fMP4 muxer → pipe:1
                                                                       ↓
                                                              Node.js stdout handler
                                                                       ↓
                                                              MP4 box accumulator (pipeBuf)
                                                                       ↓
                                                    ┌── ftyp box → initSegment (cached)
                                                    ├── moov box → initSegment (cached)
                                                    ├── moof box → broadcast to all WS clients
                                                    └── mdat box → broadcast to all WS clients
                                                                       ↓
                                                              WebSocket /ws/stream
                                                                       ↓
                                                              Browser MSE player
                                                    ┌── MediaSource + SourceBuffer (sequence mode)
                                                    ├── appendBuffer(complete box)
                                                    ├── seekToLiveEdge() if >2s behind
                                                    └── trimBuffer() keep ~5s
```

### MP4 box parser (server-side)

The `pipeBuf` accumulator in `startFfmpegWs()` works as follows:

1. Concatenate incoming pipe data to `pipeBuf`
2. Check if buffer has at least 8 bytes (MP4 box header: 4-byte size + 4-byte type)
3. Read `boxSize` from first 4 bytes (big-endian uint32)
4. If `pipeBuf.length < boxSize` → wait for more data
5. If `boxSize < 8` or `boxSize > 50MB` → invalid, reset buffer (safety valve)
6. Extract `boxSize` bytes as a complete box, advance `pipeBuf`
7. Route by box type:
   - `ftyp` → append to `initSegment`
   - `moov` → append to `initSegment`, mark init as complete
   - `moof` / `mdat` → `broadcast()` to all WebSocket clients
8. Repeat from step 2 (multiple boxes may arrive in one pipe chunk)

### Client connection flow

1. Page loads → calls `GET /api/status` first (never blindly loads HLS)
2. If `ffmpeg: false` → shows "FFmpeg not running" overlay (no spinner)
3. If `streamReady: false` → shows "FFmpeg starting..." overlay (with spinner)
4. If `streamReady: true` → connects in the appropriate mode:
   - **HLS:** creates HLS.js instance, loads `/hls/screen.m3u8`, plays on `MANIFEST_PARSED`
   - **WS:** opens WebSocket to `/ws/stream`, creates `MediaSource` + `SourceBuffer` (`sequence` mode, codec `avc1.42C01F`), appends incoming boxes, auto-seeks to live edge
5. If `video.play()` rejects (autoplay blocked) → shows "Click to Play" button
6. On error/disconnect → exponential backoff retry (5s → 10s → 15s cap, resets on success)

### Late-join (WS mode)

When a new WebSocket client connects:
1. Server sends the cached `initSegment` (ftyp + moov, ~774 bytes) immediately
2. Client's `SourceBuffer` receives the init segment, initializes the codec
3. Subsequent moof+mdat boxes arrive and are appended
4. `seekToLiveEdge()` positions playback at `bufferEnd - 0.5s`
5. Video starts playing near real-time

### Buffer management (WS mode)

| Mechanism | Threshold | Action |
|---|---|---|
| Live edge seek | `bufferEnd - currentTime > 2s` | `video.currentTime = bufferEnd - 0.5` |
| Buffer trim | `bufferEnd - bufferStart > 5s` | `sourceBuffer.remove(start, end - 3)` |
| Pending queue cap | `pendingBuffers.length > 30` | Drop oldest (shift) |
| Force trim | `QuotaExceededError` on append | Immediate trim + queue the chunk |

### Mode switching flow

1. User clicks "Low Latency" or "HLS" toggle
2. `POST /api/mode` → server sets `streamMode`, clears `initSegment`, kills FFmpeg
3. Client immediately calls `destroyHls()` + `destroyWs()` (tears down current player)
4. Shows "Switching to..." overlay
5. FFmpeg's `close` event fires → `scheduleRestart()` → 3 second delay → `startCurrentMode()`
6. Client's `setTimeout(checkAndConnect, 3000)` polls `/api/status`, sees `streamReady: true`, connects

### Quality switching flow

Same as mode switching but only restarts FFmpeg with new resolution/bitrate preset. The streaming mode stays the same.

## Graceful Shutdown

The stop sequence (triggered by `stop.bat`, SIGTERM, SIGINT, or `stop.flag`):

1. Set `shuttingDown = true` (prevents `scheduleRestart` from firing)
2. Close all WebSocket clients (`ws.close()` for each, then `wsClients.clear()`)
3. Send SIGTERM to FFmpeg process
4. Delete all files in `stream/` directory
5. Exit after 1 second

The `stop.flag` mechanism enables Windows-friendly shutdown without signals — `setInterval` checks every 2 seconds for the flag file, deletes it, then calls `shutdown()`.

`stop.bat` creates the flag, waits 3 seconds for graceful shutdown, then force-kills any remaining `node.exe` (matching "ServerPages" in command line) and `ffmpeg.exe` processes.

## Logging

- **File:** `logs/serverpages.log`
- **Rotation:** auto-rotates at 5MB (renames to `.log.old`, keeps one backup)
- **Format:** `[ISO-8601-timestamp] message`
- **What's logged:**
  - Server start/stop
  - FFmpeg start (PID, quality, mode), exit (code), errors
  - WS mode: init segment cached (size), box parser warnings
  - WebSocket client connect/disconnect (with total count)
  - Mode changes, quality changes
  - Shutdown signals
- **Filtered out:** FFmpeg frame progress lines (`frame=...`) to reduce noise

## File Structure

```
D:\ServerPages\
  bin/
    ffmpeg.exe              ← downloaded by setup.bat (~130MB)
    launch-hidden.vbs       ← VBS wrapper: finds node.exe via PATH, runs server.js with window style 0 (hidden)
  deps/                     ← optional: pre-downloaded installers (node-setup.msi, tailscale-setup.msi, ffmpeg.zip)
  stream/                   ← HLS segments (auto-cleaned on shutdown, empty in WS mode)
  logs/
    serverpages.log         ← app log (auto-rotated at 5MB)
    serverpages.log.old     ← previous log (one backup)
  server/
    server.js               ← Express + WebSocket server, FFmpeg manager, MP4 box parser, REST API (627 lines)
    package.json            ← dependencies: express ^4.21.0, ws ^8.19.0
    package-lock.json
    node_modules/
    public/
      index.html            ← Dashboard: status-first stream preview (HLS) or mode label (WS), media browser card
      live.html             ← Live stream: HLS.js player + WebSocket/MSE player, mode toggle, quality toggle, overlay states (548 lines)
      media.html            ← File browser: drive selector, breadcrumb nav, directory listing, inline video/audio/image player, download buttons
      style.css             ← Dark theme with CSS custom properties (--bg, --surface, --accent, etc.)
  install.bat               ← One-click installer: downloads repo zip from GitHub, extracts, runs setup.bat
  setup.bat                 ← Full setup: Node.js, FFmpeg, npm install, Task Scheduler XML, Tailscale login+funnel, tray hide (281 lines)
  start.bat                 ← Manual start: checks prerequisites, runs launch-hidden.vbs
  stop.bat                  ← Manual stop: creates stop.flag → waits 3s → force kills node+ffmpeg → cleans stream/
  stop.flag                 ← transient: created by stop.bat, polled and deleted by server
```

## Server Internals (`server.js`)

### Functions

| Function | Lines | Purpose |
|---|---|---|
| `log(msg)` | 33-48 | Timestamped logging to console + file, auto-rotates at 5MB |
| `killOrphanedFfmpeg()` | 51-68 | On startup, runs `tasklist` to find ffmpeg.exe PIDs, kills them with `taskkill /F` |
| `startFfmpeg()` | 98-168 | Spawns FFmpeg in HLS mode: gdigrab → libx264 → HLS muxer → `stream/screen.m3u8` |
| `startFfmpegWs()` | 171-283 | Spawns FFmpeg in WS mode: gdigrab → libx264 → fMP4 `pipe:1`. Contains the MP4 box accumulator (`pipeBuf`) that parses box headers and only broadcasts complete boxes. Caches ftyp+moov as `initSegment`. |
| `broadcast(data)` | 286-292 | Iterates `wsClients`, sends binary data to all with `readyState === OPEN` |
| `startCurrentMode()` | 295-301 | Delegates to `startFfmpeg()` or `startFfmpegWs()` based on `streamMode` |
| `scheduleRestart()` | 303-314 | 3-second debounced restart: sets `ffmpegRestarting` flag, calls `killOrphanedFfmpeg()` then `startCurrentMode()` |
| `isPathAllowed(path)` | 317-324 | Resolves path, checks it starts with an allowed root (C:\ or D:\) |
| `isMediaFile(path)` | 326-328 | Checks file extension against `MEDIA_EXTS` set |
| `cleanStreamDir()` | 88-96 | Deletes all files in `stream/` directory |
| `shutdown(signal)` | 557-581 | Graceful shutdown: closes WS clients, kills FFmpeg, cleans stream dir, exits after 1s |

### Express Routes

| Method | Route | Handler |
|---|---|---|
| GET | `/api/status` | Returns JSON: ffmpeg running, PID, uptime, streamReady, streamMode, quality, wsClients count |
| POST | `/api/mode` | Validates mode (`hls`/`ws`), updates `streamMode`, clears `initSegment`, kills FFmpeg (auto-restarts in new mode) |
| POST | `/api/quality` | Validates quality (`720p`/`1080p`), updates `currentQuality`, kills FFmpeg (auto-restarts with new preset) |
| GET | `/api/files` | Lists directories + media files for given `dir` query param. Skips system dirs (`$*`, `System Volume Information`). Returns sorted dirs + files with size/type/modified. |
| GET | `/api/stream` | Streams media file with HTTP Range support (206 Partial Content). Maps 50+ extensions to MIME types. |
| GET | `/api/download` | Sends file as download attachment via `res.download()` |
| Static | `/` | Serves `public/` directory (index.html, live.html, media.html, style.css) |
| Static | `/hls/*` | Serves `stream/` directory with correct MIME types (`.m3u8` → `application/vnd.apple.mpegurl`, `.ts` → `video/mp2t`) |

### WebSocket Server

- Path: `/ws/stream`
- Created on the same HTTP server (port 3333) via `new WebSocketServer({ server, path })`
- On connection: adds client to `wsClients` Set, sends cached `initSegment` if available
- On close/error: removes client from `wsClients`
- On shutdown: iterates all clients, calls `ws.close()`, then `wsClients.clear()`

### State Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `streamMode` | `'hls' \| 'ws'` | `'hls'` | Current streaming mode — determines which FFmpeg starter to use |
| `ffmpegProcess` | `ChildProcess \| null` | `null` | Active FFmpeg child process reference |
| `ffmpegRestarting` | `boolean` | `false` | Debounce flag — prevents multiple concurrent restart timers |
| `currentQuality` | `'720p' \| '1080p'` | `'720p'` | Active quality preset for FFmpeg encoding |
| `wsClients` | `Set<WebSocket>` | empty | All currently connected WebSocket viewer clients |
| `initSegment` | `Buffer \| null` | `null` | Cached fMP4 init segment (ftyp+moov boxes) sent to new WS clients for instant decoder init |
| `shuttingDown` | `boolean` | `false` | Set on shutdown to prevent `scheduleRestart()` from firing |

## Client Internals (`live.html`)

### Player Modes

| Mode | Library | Connection | Codec |
|---|---|---|---|
| HLS | HLS.js | `GET /hls/screen.m3u8` | H.264 in MPEG-TS segments |
| WS | Native MSE | `WebSocket /ws/stream` | H.264 in fMP4 boxes, codec string `avc1.42C01F` (Constrained Baseline L3.1) |

### Key Client Functions

| Function | Purpose |
|---|---|
| `checkAndConnect()` | Fetches `/api/status`, shows appropriate overlay, connects in current mode |
| `connectHls()` | Tears down WS, creates HLS.js instance, loads manifest, handles errors |
| `connectWs()` | Tears down HLS, opens WebSocket, creates MediaSource + SourceBuffer (sequence mode), appends chunks |
| `seekToLiveEdge()` | If `bufferEnd - currentTime > 2s`, seeks to `bufferEnd - 0.5s` |
| `appendBuffer(data)` | Appends to SourceBuffer if not updating, else queues (max 30 pending) |
| `flushPending()` | Called on `updateend` — shifts next chunk from `pendingBuffers` and appends |
| `trimBuffer(force)` | Removes old buffered data when >5s accumulated (or immediately on force) |
| `destroyHls()` | Destroys HLS.js instance |
| `destroyWs()` | Removes canplay listener, closes WebSocket (nulls handlers first to prevent reconnect), ends MediaSource, clears pending buffers |
| `switchMode(mode)` | POSTs to `/api/mode`, immediately destroys both players, shows overlay, reconnects after 3s |
| `setQuality(quality)` | POSTs to `/api/quality`, shows overlay, reconnects after 4s |
| `showOverlay(text, spinner)` | Shows overlay with text and optional spinner animation |
| `showPlayButton()` | Shows "Click to Play" button when autoplay is blocked |
| `scheduleRetry()` | Exponential backoff: delay doubles from 5s up to 15s cap |

### Overlay States

| State | Text | Spinner | Trigger |
|---|---|---|---|
| Checking | "Checking stream..." | Yes | Page load / retry |
| No FFmpeg | "FFmpeg not running" | No | `status.ffmpeg === false` |
| Starting | "FFmpeg starting..." | Yes | `status.streamReady === false` |
| Connecting HLS | "Connecting (HLS)..." | Yes | HLS mode, stream ready |
| Connecting WS | "Connecting (Low Latency)..." | Yes | WS mode, stream ready |
| Switching | "Switching to Low Latency/HLS..." | Yes | Mode toggle clicked |
| Quality | "Switching to 720p/1080p..." | Yes | Quality toggle clicked |
| Offline | "Stream offline — reconnecting..." | No | HLS fatal error / WS close |
| Unreachable | "Server unreachable" | No | fetch() throws |
| Lost | "Connection lost — reconnecting..." | No | WebSocket onclose |
| Autoplay | "Autoplay blocked" + Play button | No | `video.play()` rejected |
| No MSE | "MediaSource not supported..." | No | Browser lacks MSE API |
| No codec | "Codec not supported" | No | `addSourceBuffer()` throws |

## Dashboard Internals (`index.html`)

- Polls `/api/status` every 5 seconds
- Shows mode tag ("HLS" or "LOW LATENCY") in stream card header
- In HLS mode: initializes HLS.js preview player (muted, autoplay)
- In WS mode: shows "Low Latency mode — click to watch" (no MSE preview to avoid complexity)
- Status-first check: shows "FFmpeg not running" / "FFmpeg starting..." / "Server unreachable" instead of infinite spinner

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Infinite spinner on live page | Old code loaded HLS without checking status | Fixed: status-first check before connecting |
| WS mode shows nothing | FFmpeg level 3.0 too low for 720p, codec mismatch | Fixed: auto-level, codec `avc1.42C01F` |
| WS plays one frame then stops | Raw pipe chunks split MP4 boxes at arbitrary boundaries | Fixed: server-side box accumulator sends only complete boxes |
| WS plays then freezes | Wall-clock timestamps cause buffer to drift ahead of currentTime | Fixed: `sequence` mode + `seekToLiveEdge()` |
| WS reconnect leaks listeners | `canplay` handler not removed on cleanup | Fixed: tracked in `canPlayHandler`, removed in `destroyWs()` |
| Mode switch causes stale errors | Old player not destroyed during 3s restart wait | Fixed: immediate `destroyHls()` + `destroyWs()` on switch |
