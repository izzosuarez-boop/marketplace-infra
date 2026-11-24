# Production infrastructure for a FastAPI marketplace — Docker, Caddy, Redis, Grafana

The container and edge setup behind a live two-sided marketplace: a FastAPI
backend served over automatic HTTPS, horizontally scaled workers with a shared
rate-limit store, an isolated job scheduler, and a locked-down observability
dashboard. Every service is hardened and resource-capped.

This is the real production `docker-compose.prod.yml`, `Dockerfile` and
`Caddyfile` with domain, keys and provider names genericized 
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
