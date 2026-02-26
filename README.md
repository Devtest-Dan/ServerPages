# ServerPages

Silent screen broadcaster + media file server accessible over the internet.

## What it does

- **Live screen stream** — captures your desktop at 720p30 via FFmpeg → HLS, playable in any browser
- **Media file browser** — browse and play video, audio, and image files on C: and D: drives
- **Internet accessible** — free HTTPS URL via Tailscale Funnel, no port forwarding needed
- **Zero interaction** — starts on Windows login, runs hidden, auto-restarts if killed

## Architecture

```
node.exe (Express server on :3333)
  └── ffmpeg.exe (screen capture → HLS segments)

Task Scheduler "ServerPages" → restarts node.exe on failure
Tailscale Funnel → proxies :3333 to https://<machine>.ts.net
```

**2 processes in Task Manager:** `node.exe` + `ffmpeg.exe`

## Pages

| URL | Description |
|---|---|
| `/` | Dashboard — live stream preview + media browser link |
| `/live.html` | Full live screen stream (HLS.js player) |
| `/media.html` | File browser + inline player + download |

## API

| Method | Route | Description |
|---|---|---|
| GET | `/api/files?dir=C:/` | List directories + media files |
| GET | `/api/stream?path=...` | Stream file (Range support for seeking) |
| GET | `/api/download?path=...` | Download file |
| GET | `/api/status` | Server + FFmpeg status |
| GET | `/hls/screen.m3u8` | Live HLS manifest |

## Supported formats

- **Video:** mp4, mkv, avi, mov, wmv, flv, webm, m4v, mpg, mpeg, 3gp, 3g2, ts, mts, m2ts, vob, ogv, f4v, asf, rm, rmvb
- **Audio:** mp3, wav, flac, aac, ogg, wma, m4a, opus
- **Image:** jpg, jpeg, png, gif, bmp, webp, svg, ico, tiff, tif, heic, heif, avif

## Setup

### Prerequisites
- [Node.js](https://nodejs.org/) (v18+)
- [Tailscale](https://tailscale.com/download) (for internet access)

### One-time setup

```
setup.bat
```

This downloads FFmpeg, installs npm dependencies, creates a Task Scheduler entry, and prints Tailscale instructions.

### Tailscale Funnel (internet access)

```
tailscale login
tailscale funnel --bg 3333
```

Gives you a stable HTTPS URL like `https://your-machine.tailXXXXX.ts.net`.

### Manual start/stop

```
start.bat    # start in background
stop.bat     # graceful stop
```

After setup, everything auto-starts on login — no manual intervention needed.

## Auto-restart

| Scenario | Recovery |
|---|---|
| ffmpeg.exe killed | node.exe respawns it in <5 seconds |
| node.exe killed | Task Scheduler restarts it in ~1 minute |
| Both killed | Task Scheduler → node.exe → ffmpeg.exe |
| Reboot | Task Scheduler triggers on logon |

## Resource usage

| Process | CPU | RAM |
|---|---|---|
| Node.js | <1% | ~40MB |
| FFmpeg (720p30) | 5-10% | ~50MB |

## Security

- File browser restricted to C:\ and D:\ drives
- Only media file extensions are served (no exe, dll, etc.)
- Path traversal protection
- No authentication (by design)
- Tailscale URL is not publicly discoverable

## File structure

```
D:\ServerPages\
  bin/ffmpeg.exe          ← downloaded by setup.bat
  stream/                 ← HLS segments (auto-cleaned)
  logs/serverpages.log     ← app log (auto-rotated at 5MB)
  server/
    server.js             ← Express app + FFmpeg manager
    package.json
    public/
      index.html          ← Dashboard
      live.html           ← Live stream player
      media.html          ← File browser + player
      style.css           ← Dark theme
  setup.bat               ← One-time setup
  start.bat               ← Manual start
  stop.bat                ← Manual stop
```
