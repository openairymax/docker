# Docker Secrets — `secrets/` Directory

This directory is the **secret workspace** for the Airymax Docker deployment.
It holds generated secret files (never committed) plus the documentation for
generating and consuming them.

## Contents

| Entry | Purpose |
|-------|---------|
| `DOCKER_SECRETS_GUIDE.md` | Full secret-management guide, including the optional Docker Swarm secrets workflow |
| `SECRETS_TEMPLATE.md` | Template documenting each secret and the variable that consumes it |
| `*.txt` | Generated secret files (created by `scripts/generate-secrets.sh`, `chmod 600`, **gitignored**) |
| `.gitkeep` | Keeps the (otherwise empty) directory tracked in git |

## Workflow: generate secrets

```bash
# from the repository root
./scripts/generate-secrets.sh            # interactive, dev defaults
./scripts/generate-secrets.sh --prod     # production-grade lengths
./scripts/generate-secrets.sh --auto     # non-interactive
```

The script writes strong random values as individual files:

| File | Consumed by |
|------|-------------|
| `postgres_password.txt` | PostgreSQL `POSTGRES_PASSWORD` |
| `redis_password.txt` | Redis `REDIS_PASSWORD` |
| `jwt_secret.txt` | Gateway `GATEWAY_JWT_SECRET` |
| `grafana_password.txt` | Grafana admin password |
| `openai_api_key.txt` / `deepseek_api_key.txt` | Optional LLM provider keys |

Every file is written with `0600` permissions and is covered by the
repository's `.gitignore` rules, so real secrets can never be committed.

## Workflow: consume secrets

The shipped Compose manifests read configuration from an env file:

```bash
cp .env.production.example .env.production
./scripts/generate-secrets.sh
# Copy each generated value into the matching variable in .env.production,
# then launch:
docker compose -f docker-compose.prod.yml --env-file .env.production up -d
```

Note: the Compose manifests do **not** declare Docker Swarm `secrets:` entries
themselves — the env-file path above is the supported integration for Compose
deployments.

## Optional: Docker Swarm secrets

For Swarm deployments, prefer native secrets over env files:

```bash
docker secret create agentrt_postgres_password secrets/postgres_password.txt
```

See [`DOCKER_SECRETS_GUIDE.md`](DOCKER_SECRETS_GUIDE.md) for the complete
walkthrough (naming conventions, rotation, and `secrets:` service wiring
examples).

## Rules

- Never commit real secrets — only the templates and this README belong in
  git.
- Keep generated files at `0600` and share them through a secret manager,
  never through chat or email.
- Rotate with `scripts/generate-secrets.sh`, then update the target env file
  or deployment.
- If a secret is exposed, rotate it immediately and audit access logs.
