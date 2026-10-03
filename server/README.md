# Lumen gateway (`lumen_server`)

A small Dart `shelf` service that proxies vision auto-edit requests from the
Lumen app to Claude. The Anthropic API key lives only here (environment
variable), never in the app. Contract: `docs/PLAN.md` §1.9; DTOs, schema and
clamping are shared with the app through `packages/lumen_core/lib/src/api/`.

Without a key the gateway still runs: `/v1/health` reports
`visionAvailable: false` and the edit routes answer `503 vision_unavailable`,
so the app falls back to its offline engine.

## Run

```sh
cd server
dart run bin/server.dart                          # no key: health only, edits 503
ANTHROPIC_API_KEY=... dart run bin/server.dart    # vision on
curl -s localhost:8080/v1/health
```

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `ANTHROPIC_API_KEY` | unset | Enables vision. Never logged. |
| `LUMEN_MODEL` | `claude-opus-5-5` | Upstream model. |
| `LUMEN_EFFORT` | `low` | `output_config.effort`, always sent (`low/medium/high/xhigh/max`). |
| `PORT` | `8080` | Listen port. |
| `LUMEN_GATEWAY_TOKEN` | unset | When set, edit routes require `Authorization: Bearer <token>` (health stays public). |
| `LUMEN_RPM` / `LUMEN_BURST` | `20` / `5` | Token bucket per client IP. |
| `LUMEN_TRUST_PROXY` | unset | `1` = key the rate limit on the first `x-forwarded-for` hop (Cloud Run, load balancers). |
| `LUMEN_MAX_BODY_BYTES` | `4194304` | Body limit (413 above it). |
| `LUMEN_UPSTREAM_CONCURRENCY` / `LUMEN_UPSTREAM_QUEUE` | `4` / `16` | Concurrent Claude calls and waiting requests (429 when full). |
| `LUMEN_UPSTREAM_TIMEOUT_S` | `90` | Deadline across both attempts (504 after it). |
| `LUMEN_CACHE_SIZE` | `256` | In-memory LRU result cache entries (0 disables). |
| `LUMEN_CORS_ORIGIN` | `*` | `access-control-allow-origin`. |
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | Upstream base URL. |

Malformed values stop the server at startup (exit code 64).

## Endpoints

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/health` | Liveness + capability, no auth, no rate limit. |
| POST | `/v1/auto-edit` | Style-driven edit; values are absolute. |
| POST | `/v1/instruct` | Same body + `instruction`; values are deltas from `current`. |

Every response carries `x-request-id`. Errors use the envelope
`{"error": {"code", "message", "retryable", "retryAfterMs"?, "details"}, "requestId"}`:
`invalid_request`/`unsupported_contract` 400, `unauthorized` 401, `not_found` 404,
`payload_too_large` 413 (body or image long edge > 1568 px), `upstream_refusal` 422,
`rate_limited` 429 (+ `Retry-After`), `internal_error` 500,
`upstream_error`/`upstream_incomplete`/`upstream_invalid_output` 502,
`vision_unavailable` 503, `upstream_timeout` 504.

Pipeline: request id → CORS → error envelope → bearer auth → rate limit → body
limit → routes. Each edit: validate → LRU cache → upstream semaphore → Claude
(`/v1/messages`, structured output, cached system prompt, one retry on
429/529/5xx honoring `retry-after`) → check `stop_reason` → parse tolerantly →
clamp to `ParamRegistry` ranges → drop locked params → meter usage → cache.

## Tests

```sh
cd server && dart analyze && dart test     # mocked Claude (package:http/testing), no network
```

## Real-key smoke test

Runs only when a key is available; otherwise prints `not run: no key` and
exits 0.

```sh
cd server
ANTHROPIC_API_KEY=... dart run tool/smoke_vision.dart                 # in-process
# or against a running gateway:
ANTHROPIC_API_KEY=... dart run bin/server.dart &
LUMEN_GATEWAY_URL=http://localhost:8080 dart run tool/smoke_vision.dart
```

It sends a synthetic dark tungsten interior and checks: HTTP 200, at least 3
adjustments, median luma after applying the edit (CPU reference render) in
[0.30, 0.60], and that the second identical call is a cache hit or reports
`cacheReadTokens > 0`.

## Docker

Build from the repository root (the server uses the pub workspace):

```sh
docker build -f server/Dockerfile -t lumen-gateway .
docker run --rm -p 8080:8080 -e ANTHROPIC_API_KEY lumen-gateway
```

The image is an AOT binary (`dart compile exe`) on `scratch`, running as an
unprivileged user. Pass the key at run time; never bake it into the image.

## Prompt versioning

`lib/src/prompt/system_prompt.dart` builds the system prompt from
`ParamRegistry`, the style table and fixed rules. It is byte-stable so Claude's
prompt cache hits. Bump `kPromptVersion` whenever the prompt, registry or
schema changes; it is part of the result-cache key and is reported by
`/v1/health`.
