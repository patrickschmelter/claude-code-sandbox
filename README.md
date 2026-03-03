# Claude Code Sandbox

Fully sandboxed Docker environment for securely evaluating [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Security

- **Network Sandbox:** iptables firewall blocks all outbound traffic except Anthropic API, GitHub, package registries, DNS and SSH
- **Minimal Capabilities:** `cap_drop: ALL`, only NET_ADMIN/NET_RAW (firewall) and SETUID/SETGID (user switch)
- **Non-Root:** Container runs as `node` user (UID 1000)
- **Isolated:** No access to host filesystem except the explicitly shared `shared/` directory

## Prerequisites

- Docker and Docker Compose

## Quickstart

```bash
# 1. Build and start the container
docker compose up -d --build

# 2. Open a shell
docker compose exec -u node claude-code bash

# 3. Start Claude Code
claude

# 4. Stop the container
docker compose down
```

## File Sharing

The `shared/` directory is mounted between host and container:

| Host        | Container            |
| ----------- | -------------------- |
| `./shared/` | `/home/node/shared/` |

## VS Code Dev Container

1. Install the [Dev Containers Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Ctrl+Shift+P → **Dev Containers: Reopen in Container**
3. Open a terminal → `claude`

## Configuration

| Variable              | Description                                      | Default  |
| --------------------- | ------------------------------------------------ | -------- |
| `CLAUDE_CODE_VERSION` | Claude Code version (build arg)                  | `latest` |
| `FIREWALL_ENABLED`    | Enable/disable the network firewall (via `.env`) | `true`   |

Additional API keys or environment variables can be added to `.env` as needed (e.g. `ANTHROPIC_API_KEY`).

Pin a specific version:

```bash
docker compose build --build-arg CLAUDE_CODE_VERSION=1.0.0
```

## Allowed Network Destinations

The firewall only permits connections to the following domains (configured in `allowed-domains.txt`):

| Category                  | Destinations                                                                                          |
| ------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Anthropic**             | `api.anthropic.com`                                                                                   |
| **GitHub**                | `github.com`, `api.github.com`, `codeload.github.com`, `*.githubusercontent.com` + GitHub IP ranges   |
| **JavaScript/TypeScript** | `registry.npmjs.org`, `registry.yarnpkg.com`                                                          |
| **Python**                | `pypi.org`, `files.pythonhosted.org`                                                                  |
| **Java/Kotlin**           | `repo.maven.apache.org`, `repo1.maven.org`, `plugins.gradle.org`, `dl.google.com`, `maven.google.com` |
| **Rust**                  | `crates.io`, `static.crates.io`, `static.rust-lang.org`                                               |
| **Go**                    | `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com`                                        |
| **Ruby**                  | `rubygems.org`, `index.rubygems.org`                                                                  |
| **PHP**                   | `packagist.org`, `repo.packagist.org`                                                                 |
| **.NET/C#**               | `api.nuget.org`, `globalcdn.nuget.org`, `dotnetcli.azureedge.net`                                     |
| **Docker Hub**            | `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com`                          |
| **VS Code Marketplace**   | `marketplace.visualstudio.com`, `gallerycdn.vsassets.io`, `vscode.blob.core.windows.net`              |
| **Telemetry**             | `sentry.io`, `statsig.anthropic.com`, `statsig.com`                                                   |
| **Infrastructure**        | DNS (port 53), SSH (port 22), localhost                                                               |

Everything else is blocked (REJECT).

## Project Structure

```
├── .devcontainer/
│   └── devcontainer.json   # VS Code Dev Container configuration
├── Dockerfile              # Container image (node:20 + Claude Code)
├── docker-compose.yml      # Standalone operation
├── entrypoint.sh           # Firewall init + user switch (gosu)
├── init-firewall.sh        # iptables/ipset network sandbox
├── allowed-domains.txt     # Whitelisted domains for the firewall
├── .env.example            # Environment variable template
├── shared/                 # Shared directory with host
└── .gitignore
```
