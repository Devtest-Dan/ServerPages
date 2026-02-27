# ServerPages

Silent screen broadcaster + media file server accessible over the internet.

## What it does

- **Live screen stream** — captures your desktop via FFmpeg → HLS, playable in any browser (720p/1080p toggle)
- **Media file browser** — browse and play video, audio, and image files on C: and D: drives
- **Internet accessible** — free HTTPS URL via Tailscale Funnel, no port forwarding needed
- **Zero interaction** — starts on any user login, runs fully hidden (no console window, no tray icon), auto-restarts if killed

## Architecture

```
wscript.exe → node.exe (Express server on :3333, hidden window)
                └── ffmpeg.exe (screen capture → HLS segments)

Task Scheduler "ServerPages" → triggers on any user logon, restarts on failure
Tailscale service (unattended) → Funnel proxies :3333 to https://<machine>.ts.net
```

**2 visible processes in Task Manager:** `node.exe` + `ffmpeg.exe` (no console window)
**Tailscale:** runs as a Windows service — no GUI, no tray icon

## Pages

| URL | Description |
|---|---|
| `/` | Dashboard — live stream preview + media browser link |
| `/live.html` | Full live screen stream (HLS.js player, 720p/1080p toggle) |
| `/media.html` | File browser + inline player + download |

## API

| Method | Route | Description |
|---|---|---|
| GET | `/api/files?dir=C:/` | List directories + media files |
| GET | `/api/stream?path=...` | Stream file (Range support for seeking) |
| GET | `/api/download?path=...` | Download file |
| GET | `/api/status` | Server + FFmpeg status + current quality |
| POST | `/api/quality` | Set stream quality (`{"quality":"720p"}` or `{"quality":"1080p"}`) |
| GET | `/hls/screen.m3u8` | Live HLS manifest |

## Supported formats

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

1. Installs Node.js (if missing)
2. Downloads FFmpeg (if missing)
3. Installs npm dependencies
4. Creates Task Scheduler entry (any user logon, hidden, restart on failure)
5. Configures Tailscale (login, unattended mode, Funnel on port 3333)
6. Removes Tailscale tray icon

### Internet URL

`https://<machine-name>.tailXXXXX.ts.net`

Replace `<machine-name>` with whatever Tailscale assigns to the machine.

### Manual start/stop

```
start.bat    # start in background (hidden)
stop.bat     # graceful stop
```

After setup, everything auto-starts on any user login — fully hidden, no manual intervention needed.

## Auto-restart

| Scenario | Recovery |
|---|---|
| ffmpeg.exe killed | node.exe respawns it in <5 seconds |
| node.exe killed | Task Scheduler restarts it in ~1 minute |
| Both killed | Task Scheduler → node.exe → ffmpeg.exe |
| Reboot | Task Scheduler triggers on any user logon |

## Resource usage

| Process | CPU (720p) | CPU (1080p) | RAM |
|---|---|---|---|
| Node.js | <1% | <1% | ~40MB |
| FFmpeg | 5-10% | 10-15% | ~50MB |

## Security

- File browser restricted to C:\ and D:\ drives
- Only media file extensions are served (no exe, dll, etc.)
- Path traversal protection
- No authentication (by design)
- Tailscale URL is not publicly discoverable

## File structure

```
D:\ServerPages\
  bin/
    ffmpeg.exe            ← downloaded by setup.bat
    launch-hidden.vbs     ← VBS wrapper to run node.exe with no console window
  stream/                 ← HLS segments (auto-cleaned)
  logs/serverpages.log    ← app log (auto-rotated at 5MB)
  server/
    server.js             ← Express app + FFmpeg manager
    package.json
    public/
      index.html          ← Dashboard
      live.html           ← Live stream player
      media.html          ← File browser + player
      style.css           ← Dark theme
  install.bat              ← One-click installer (new machines)
  setup.bat               ← Full setup (Node.js, FFmpeg, Tailscale, Task Scheduler)
  start.bat               ← Manual start
  stop.bat                ← Manual stop
```
