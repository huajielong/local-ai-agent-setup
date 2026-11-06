// Chat request sanitizer for Claude Code -> Anthropic proxy -> llama.cpp.
//
// Claude Code 2.1.x sends some context (environment info, environment updates)
// as role:"system" messages inside the messages array. Qwen/llama.cpp Jinja
// templates require system messages to be the very first message, so any
// mid-conversation system message makes llama-server return:
//   500 Jinja Exception: System message must be at the beginning.
//
// This relay listens on the public port Claude Code uses, moves every
// mid-conversation system message into the top-level `system` prompt, and
// forwards the rewritten request to anthropic-proxy on the internal port.
//
// Env:
//   SANITIZER_LISTEN_PORT   (default 8787)
//   SANITIZER_UPSTREAM_PORT (default 8788)
//   SANITIZER_UPSTREAM_HOST (default 127.0.0.1)

const http = require('http');

const LISTEN_PORT = parseInt(process.env.SANITIZER_LISTEN_PORT || '8787', 10);
const UPSTREAM_PORT = parseInt(process.env.SANITIZER_UPSTREAM_PORT || '8788', 10);
const UPSTREAM_HOST = process.env.SANITIZER_UPSTREAM_HOST || '127.0.0.1';

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((b) => {
        if (!b) return '';
        if (b.type === 'text' && typeof b.text === 'string') return b.text;
        if (typeof b.text === 'string') return b.text;
        return '';
      })
      .filter(Boolean)
      .join('\n\n');
  }
  if (content && typeof content.text === 'string') return content.text;
  return '';
}

function sanitize(body) {
  if (!body || !Array.isArray(body.messages)) return 0;

  const kept = [];
  const moved = [];
  for (const m of body.messages) {
    if (m && m.role === 'system') {
      const t = textOf(m.content);
      if (t) moved.push(t);
    } else {
      kept.push(m);
    }
  }
  if (moved.length === 0) return 0;

  if (Array.isArray(body.system)) {
    for (const t of moved) body.system.push({ type: 'text', text: t });
  } else if (typeof body.system === 'string' && body.system.length > 0) {
    body.system = [{ type: 'text', text: body.system }].concat(
      moved.map((t) => ({ type: 'text', text: t }))
    );
  } else if (body.system && typeof body.system === 'object') {
    body.system = [body.system].concat(moved.map((t) => ({ type: 'text', text: t })));
  } else {
    body.system = moved.map((t) => ({ type: 'text', text: t }));
  }

  body.messages = kept;
  return moved.length;
}

function log(msg) {
  process.stdout.write(new Date().toISOString() + ' ' + msg + '\n');
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }

  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    let body = Buffer.concat(chunks);

    if (req.method === 'POST') {
      try {
        const parsed = JSON.parse(body.toString('utf8'));
        const moved = sanitize(parsed);
        if (moved > 0) {
          body = Buffer.from(JSON.stringify(parsed), 'utf8');
          log(`hoisted ${moved} mid-conversation system message(s) into system prompt`);
        }
      } catch (e) {
        log(`request left unchanged (parse error: ${e.message})`);
      }
    }

    const headers = { ...req.headers, host: `${UPSTREAM_HOST}:${UPSTREAM_PORT}` };
    delete headers['content-length'];
    headers['content-length'] = Buffer.byteLength(body);

    const upstream = http.request(
      {
        host: UPSTREAM_HOST,
        port: UPSTREAM_PORT,
        path: req.url,
        method: req.method,
        headers,
      },
      (up) => {
        res.writeHead(up.statusCode, up.headers);
        up.pipe(res);
      }
    );

    upstream.on('error', (e) => {
      log(`upstream error: ${e.message}`);
      if (!res.headersSent) {
        res.writeHead(502, { 'content-type': 'text/plain' });
      }
      res.end(`sanitizer upstream error: ${e.message}`);
    });

    upstream.end(body);
  });
});

server.requestTimeout = 0;
server.headersTimeout = 0;
server.timeout = 0;

server.listen(LISTEN_PORT, '127.0.0.1', () => {
  log(`chat-sanitizer listening on 127.0.0.1:${LISTEN_PORT} -> ${UPSTREAM_HOST}:${UPSTREAM_PORT}`);
});
