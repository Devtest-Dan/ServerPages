const express = require('express');
const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// ─── Paths ───────────────────────────────────────────────────────────────────
const ROOT = path.resolve(__dirname, '..');
const FFMPEG = path.join(ROOT, 'bin', 'ffmpeg.exe');
const STREAM_DIR = path.join(ROOT, 'stream');
const LOG_FILE = path.join(ROOT, 'logs', 'serverpages.log');
const PORT = 3333;

// ─── Allowed drives for media browsing ───────────────────────────────────────
const ALLOWED_ROOTS = ['C:\\', 'D:\\'];

const VIDEO_EXTS = new Set([
  '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm',
  '.m4v', '.mpg', '.mpeg', '.3gp', '.3g2', '.ts',
  '.mts', '.m2ts', '.vob', '.ogv', '.f4v', '.asf', '.rm', '.rmvb'
]);
const AUDIO_EXTS = new Set([
  '.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a', '.opus'
]);
const IMAGE_EXTS = new Set([
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg',
  '.ico', '.tiff', '.tif', '.heic', '.heif', '.avif'
]);
const MEDIA_EXTS = new Set([...VIDEO_EXTS, ...AUDIO_EXTS, ...IMAGE_EXTS]);

// ─── Logging ─────────────────────────────────────────────────────────────────
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  try {
    // Rotate log if > 5MB
    if (fs.existsSync(LOG_FILE)) {
      const stat = fs.statSync(LOG_FILE);
      if (stat.size > 5 * 1024 * 1024) {
        const rotated = LOG_FILE + '.old';
        if (fs.existsSync(rotated)) fs.unlinkSync(rotated);
        fs.renameSync(LOG_FILE, rotated);
      }
    }
    fs.appendFileSync(LOG_FILE, line + '\n');
  } catch (e) { /* ignore log errors */ }
}

// ─── Kill orphaned ffmpeg ────────────────────────────────────────────────────
function killOrphanedFfmpeg() {
  try {
    const list = execSync('tasklist /FI "IMAGENAME eq ffmpeg.exe" /FO CSV /NH', {
      encoding: 'utf8', windowsHide: true
    });
    const pids = [];
    for (const line of list.trim().split('\n')) {
      const match = line.match(/"ffmpeg\.exe","(\d+)"/i);
      if (match) pids.push(match[1]);
    }
    for (const pid of pids) {
      try {
        execSync(`taskkill /PID ${pid} /F`, { windowsHide: true });
        log(`Killed orphaned ffmpeg PID ${pid}`);
      } catch (e) { /* already dead */ }
    }
  } catch (e) { /* no ffmpeg running */ }
}

// ─── Quality presets ─────────────────────────────────────────────────────────
const QUALITY_PRESETS = {
  '720p':  { scale: '1280:720',  bitrate: '2000k', maxrate: '2500k', bufsize: '5000k' },
  '1080p': { scale: '1920:1080', bitrate: '4000k', maxrate: '5000k', bufsize: '10000k' }
};
let currentQuality = '720p';

// ─── FFmpeg management ───────────────────────────────────────────────────────
let ffmpegProcess = null;
let ffmpegRestarting = false;

function cleanStreamDir() {
  try {
    if (fs.existsSync(STREAM_DIR)) {
      for (const f of fs.readdirSync(STREAM_DIR)) {
        fs.unlinkSync(path.join(STREAM_DIR, f));
      }
    }
  } catch (e) { /* ignore */ }
}

function startFfmpeg() {
  if (!fs.existsSync(FFMPEG)) {
    log('ERROR: ffmpeg.exe not found at ' + FFMPEG);
    log('Run setup.bat first to download FFmpeg.');
    return;
  }

  cleanStreamDir();
  fs.mkdirSync(STREAM_DIR, { recursive: true });

  const preset = QUALITY_PRESETS[currentQuality];
  log(`Quality: ${currentQuality} (${preset.scale}, ${preset.bitrate})`);

  const args = [
    '-f', 'gdigrab',
    '-framerate', '30',
    '-i', 'desktop',
    '-an',
    '-vf', `scale=${preset.scale}`,
    '-c:v', 'libx264',
    '-preset', 'ultrafast',
    '-tune', 'zerolatency',
    '-b:v', preset.bitrate,
    '-maxrate', preset.maxrate,
    '-bufsize', preset.bufsize,
    '-g', '60',
    '-keyint_min', '60',
    '-pix_fmt', 'yuv420p',
    '-f', 'hls',
    '-hls_time', '2',
    '-hls_list_size', '5',
    '-hls_flags', 'delete_segments+append_list',
    '-hls_segment_filename', path.join(STREAM_DIR, 'seg%03d.ts'),
    path.join(STREAM_DIR, 'screen.m3u8')
  ];

  log('Starting FFmpeg...');
  ffmpegProcess = spawn(FFMPEG, args, {
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe']
  });

  ffmpegProcess.stdout.on('data', (data) => {
    // FFmpeg outputs most info to stderr, stdout is usually empty
  });

  ffmpegProcess.stderr.on('data', (data) => {
    const msg = data.toString().trim();
    if (msg && !msg.startsWith('frame=')) {
      log(`FFmpeg: ${msg.substring(0, 200)}`);
    }
  });

  ffmpegProcess.on('close', (code) => {
    log(`FFmpeg exited with code ${code}`);
    ffmpegProcess = null;
    if (!shuttingDown) {
      scheduleRestart();
    }
  });

  ffmpegProcess.on('error', (err) => {
    log(`FFmpeg error: ${err.message}`);
    ffmpegProcess = null;
    if (!shuttingDown) {
      scheduleRestart();
    }
  });

  log(`FFmpeg started (PID: ${ffmpegProcess.pid})`);
}

function scheduleRestart() {
  if (ffmpegRestarting || shuttingDown) return;
  ffmpegRestarting = true;
  log('FFmpeg died — restarting in 3 seconds...');
  setTimeout(() => {
    ffmpegRestarting = false;
    if (!shuttingDown) {
      killOrphanedFfmpeg();
      startFfmpeg();
    }
  }, 3000);
}

// ─── Path security ───────────────────────────────────────────────────────────
function isPathAllowed(requestedPath) {
  try {
    const resolved = path.resolve(requestedPath);
    return ALLOWED_ROOTS.some(root => resolved.startsWith(root));
  } catch (e) {
    return false;
  }
}

function isMediaFile(filePath) {
  return MEDIA_EXTS.has(path.extname(filePath).toLowerCase());
}

function isVideoFile(filePath) {
  return VIDEO_EXTS.has(path.extname(filePath).toLowerCase());
}

function isImageFile(filePath) {
  return IMAGE_EXTS.has(path.extname(filePath).toLowerCase());
}

function getFileType(filePath) {
  if (isVideoFile(filePath)) return 'video';
  if (isImageFile(filePath)) return 'image';
  return 'audio';
}

// ─── Express app ─────────────────────────────────────────────────────────────
const app = express();

// Static files
app.use(express.static(path.join(__dirname, 'public')));

// HLS segments
app.use('/hls', express.static(STREAM_DIR, {
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.m3u8')) {
      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
      res.setHeader('Cache-Control', 'no-cache, no-store');
    } else if (filePath.endsWith('.ts')) {
      res.setHeader('Content-Type', 'video/mp2t');
      res.setHeader('Cache-Control', 'max-age=10');
    }
  }
}));

// ─── API: List files ─────────────────────────────────────────────────────────
app.get('/api/files', (req, res) => {
  const dir = req.query.dir || 'C:/';
  const dirPath = path.resolve(dir);

  if (!isPathAllowed(dirPath)) {
    return res.status(403).json({ error: 'Access denied' });
  }

  try {
    const entries = fs.readdirSync(dirPath, { withFileTypes: true });
    const dirs = [];
    const files = [];

    for (const entry of entries) {
      try {
        const fullPath = path.join(dirPath, entry.name);
        if (entry.isDirectory()) {
          // Skip system/hidden directories
          if (entry.name.startsWith('$') || entry.name === 'System Volume Information') continue;
          dirs.push({ name: entry.name, path: fullPath, type: 'directory' });
        } else if (entry.isFile() && isMediaFile(entry.name)) {
          const stat = fs.statSync(fullPath);
          files.push({
            name: entry.name,
            path: fullPath,
            type: getFileType(entry.name),
            size: stat.size,
            modified: stat.mtime.toISOString()
          });
        }
      } catch (e) {
        // Skip files we can't access
      }
    }

    // Sort: dirs alphabetically, files alphabetically
    dirs.sort((a, b) => a.name.localeCompare(b.name));
    files.sort((a, b) => a.name.localeCompare(b.name));

    res.json({
      currentDir: dirPath,
      parent: path.dirname(dirPath) !== dirPath ? path.dirname(dirPath) : null,
      dirs,
      files
    });
  } catch (e) {
    res.status(500).json({ error: 'Cannot read directory: ' + e.message });
  }
});

// ─── API: Stream file (with Range support) ───────────────────────────────────
app.get('/api/stream', (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: 'Missing path' });

  const resolved = path.resolve(filePath);
  if (!isPathAllowed(resolved) || !isMediaFile(resolved)) {
    return res.status(403).json({ error: 'Access denied' });
  }

  if (!fs.existsSync(resolved)) {
    return res.status(404).json({ error: 'File not found' });
  }

  const stat = fs.statSync(resolved);
  const fileSize = stat.size;
  const ext = path.extname(resolved).toLowerCase();

  const mimeTypes = {
    '.mp4': 'video/mp4', '.mkv': 'video/x-matroska', '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime', '.wmv': 'video/x-ms-wmv', '.flv': 'video/x-flv',
    '.webm': 'video/webm', '.m4v': 'video/x-m4v', '.mpg': 'video/mpeg',
    '.mpeg': 'video/mpeg', '.3gp': 'video/3gpp', '.3g2': 'video/3gpp2', '.ts': 'video/mp2t',
    '.mts': 'video/mp2t', '.m2ts': 'video/mp2t', '.vob': 'video/mpeg',
    '.ogv': 'video/ogg', '.f4v': 'video/mp4', '.asf': 'video/x-ms-asf',
    '.rm': 'application/vnd.rn-realmedia', '.rmvb': 'application/vnd.rn-realmedia-vbr',
    '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.flac': 'audio/flac',
    '.aac': 'audio/aac', '.ogg': 'audio/ogg', '.wma': 'audio/x-ms-wma',
    '.m4a': 'audio/mp4', '.opus': 'audio/opus',
    '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
    '.gif': 'image/gif', '.bmp': 'image/bmp', '.webp': 'image/webp',
    '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.tiff': 'image/tiff',
    '.tif': 'image/tiff', '.heic': 'image/heic', '.heif': 'image/heif',
    '.avif': 'image/avif'
  };
  const contentType = mimeTypes[ext] || 'application/octet-stream';

  const range = req.headers.range;
  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    const chunkSize = end - start + 1;

    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Content-Type': contentType
    });
    fs.createReadStream(resolved, { start, end }).pipe(res);
  } else {
    res.writeHead(200, {
      'Content-Length': fileSize,
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes'
    });
    fs.createReadStream(resolved).pipe(res);
  }
});

// ─── API: Download file ──────────────────────────────────────────────────────
app.get('/api/download', (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: 'Missing path' });

  const resolved = path.resolve(filePath);
  if (!isPathAllowed(resolved) || !isMediaFile(resolved)) {
    return res.status(403).json({ error: 'Access denied' });
  }

  if (!fs.existsSync(resolved)) {
    return res.status(404).json({ error: 'File not found' });
  }

  res.download(resolved, path.basename(resolved));
});

// ─── API: Status ─────────────────────────────────────────────────────────────
app.get('/api/status', (req, res) => {
  res.json({
    ffmpeg: ffmpegProcess !== null,
    ffmpegPid: ffmpegProcess ? ffmpegProcess.pid : null,
    uptime: process.uptime(),
    streamReady: fs.existsSync(path.join(STREAM_DIR, 'screen.m3u8')),
    quality: currentQuality
  });
});

// ─── API: Set quality ────────────────────────────────────────────────────────
app.post('/api/quality', express.json(), (req, res) => {
  const { quality } = req.body;
  if (!QUALITY_PRESETS[quality]) {
    return res.status(400).json({ error: 'Invalid quality. Use: ' + Object.keys(QUALITY_PRESETS).join(', ') });
  }
  if (quality === currentQuality) {
    return res.json({ quality: currentQuality, changed: false });
  }

  currentQuality = quality;
  log(`Quality changed to ${quality} — restarting FFmpeg...`);

  // Kill current FFmpeg, it will auto-restart with new settings
  if (ffmpegProcess) {
    try { ffmpegProcess.kill('SIGTERM'); } catch (e) {}
  } else {
    startFfmpeg();
  }

  res.json({ quality: currentQuality, changed: true });
});

// ─── Graceful shutdown ───────────────────────────────────────────────────────
let shuttingDown = false;

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log(`Received ${signal}, shutting down...`);

  if (ffmpegProcess) {
    try {
      ffmpegProcess.kill('SIGTERM');
      log('Sent SIGTERM to FFmpeg');
    } catch (e) { /* already dead */ }
  }

  cleanStreamDir();

  setTimeout(() => {
    log('Goodbye.');
    process.exit(0);
  }, 1000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Check for stop flag file (Windows-friendly shutdown)
setInterval(() => {
  const stopFlag = path.join(ROOT, 'stop.flag');
  if (fs.existsSync(stopFlag)) {
    try { fs.unlinkSync(stopFlag); } catch (e) {}
    shutdown('stop.flag');
  }
}, 2000);

// ─── Start ───────────────────────────────────────────────────────────────────
log('=== ServerPages starting ===');
killOrphanedFfmpeg();

app.listen(PORT, () => {
  log(`Server listening on http://localhost:${PORT}`);
  startFfmpeg();
});
