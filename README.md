# Production infrastructure for a FastAPI marketplace — Docker, Caddy, Redis, Grafana

The container and edge setup behind a live two-sided marketplace: a FastAPI
backend served over automatic HTTPS, horizontally scaled workers with a shared
rate-limit store, an isolated job scheduler, and a locked-down observability
dashboard. Every service is hardened and resource-capped.

This is the real production `docker-compose.prod.yml`, `Dockerfile` and
`Caddyfile` with domain, keys and provider names genericized — the engineering
is intact, the secrets are gone.

## Topology

```
          Internet
             │  (443, automatic TLS)
         ┌───▼────┐
         │  Caddy │  edge reverse proxy — Let's Encrypt, security headers,
         └───┬────┘  real-IP resolution behind a CDN, 2 MB upload cap
             │  (internal docker network only)
      ┌──────▼───────┐        ┌──────────────┐
      │   backend    │        │  scheduler   │   same image, RUN_SCHEDULER=1,
      │ 3 uvicorn    │        │  1 process   │   single process
      │ workers      │        └──────┬───────┘
      └──────┬───────┘               │
             │   ┌──────────┐        │
             └──►│  redis   │◄───────┘   shared rate-limit store
                 └──────────┘
      ┌──────────────┐
      │   grafana    │   bound to 127.0.0.1 only — reachable via SSH tunnel
      └──────────────┘
```

## The decisions worth reading

Each of these was a real production fix, not a default:

- **The backend is never published to the host.** Only Caddy reaches it, over
  the internal docker network. That is what makes `FORWARDED_ALLOW_IPS: "*"`
  safe — there is no path to the backend that doesn't come through the proxy.

- **Redis exists because of the worker count, not for caching.** Going from 1
  to 3 uvicorn workers (a single worker degraded sharply at 15–30 concurrent
  connections) turned the in-memory rate-limit counter into *three* independent
  counters — silently tripling the real limit. Redis makes it one shared
  counter again.

- **The scheduler is a separate service.** With multiple backend workers, each
  process started its own scheduler and every job (payment verification,
  escrow, settlements, expirations) ran in triplicate in production. The fix:
  `RUN_SCHEDULER=0` on the workers, a single dedicated `scheduler` service with
  `RUN_SCHEDULER=1`. The README note "always deploy backend and scheduler
  together" exists because deploying the backend alone leaves payments
  unverified.

- **Real client IP behind a CDN, without spoofing.** The proxy only trusts the
  forwarded-IP header when the request comes from a known CDN range; everything
  else falls back to the connection IP. Otherwise anyone could forge their IP
  and defeat the per-IP rate limit.

- **Grafana is bound to `127.0.0.1` only.** It is an internal tool — reaching
  it requires an SSH tunnel (`ssh -L 3001:localhost:3001 host`). It is never
  exposed publicly.

## Hardening, applied uniformly

Every service runs with `no-new-privileges:true`; application services drop
`ALL` Linux capabilities and run as a non-root user (see the `Dockerfile`);
each has explicit `mem_limit`, `cpus` and `pids_limit`; logs are size- and
count-capped so a runaway service can't fill the disk. The resource caps were
*measured*, not guessed — the previous limits were self-imposed and
confirmed oversized against the real machine.

## Files

| File | What it configures |
|---|---|
| `docker-compose.prod.yml` | The five services, their networking, limits and hardening |
| `Dockerfile` | The backend image: layer-cached deps, non-root user, `/health` healthcheck, env-driven worker count |
| `Caddyfile` | Edge: automatic HTTPS, security headers, CDN-aware real-IP, upload cap |

> Note: this repo documents the deployment topology. The `.env` (all secrets,
> domain, provider keys) is never committed — the compose file reads it via
> `env_file`, and the values shown are placeholders.
