---
display_name: BookOrbit Development
description: Provision Docker workspaces for BookOrbit development with Node 24, PostgreSQL 18, VS Code Web, and persistent project data.
icon: ../../../../.icons/docker.svg
verified: false
tags: [bookorbit, nodejs, postgres, docker]
---

# BookOrbit Development

Provision a Docker-based Coder workspace for contributing to [BookOrbit](https://github.com/bookorbit/bookorbit), including Node 24, pnpm, PostgreSQL 18 with pgvector, code-server, and the BookOrbit development server.

## Prerequisites

The Coder provisioner host must have access to a Docker daemon. If Coder runs in a container, make its Docker socket available to the provisioner and grant its process access to that socket. The workspace image is built on the provisioner host, so that host also needs outbound access to the Microsoft container registry, Docker Hub, npm, and the selected Git repository.

For a private BookOrbit fork, configure GitHub external authentication in Coder before creating a workspace. Enter the fork's HTTPS URL when creating the workspace. The default points to the maintainer's BookOrbit fork.

## Architecture

The template builds a Node 24 development image and creates a Docker workspace container linked to a PostgreSQL 18 container on a workspace-private network. The database and the developer home directory are persisted in Docker volumes; the containers and private network are recreated when a workspace is started.

On each workspace start, Coder clones the configured repository if it is not already present, installs locked pnpm dependencies, waits for PostgreSQL, applies migrations, and starts BookOrbit. The BookOrbit app is available through the workspace dashboard on port 5173. VS Code Web opens the cloned project in the browser, while Zed opens it through the Coder SSH configuration.

Codex CLI is installed with the BookOrbit checkout marked as trusted. Authenticate it inside the workspace with `codex login`. The template does not inject an OpenAI API key or enable Coder AI Gateway.

The BookOrbit app uses Coder's wildcard subdomain, so its development browser origin is configured for Vite, WebSockets, and password-reset links. The template enforces its private `postgres` database URL and `NODE_ENV=development` on startup.

To reset only the workspace's development database and generated local data, run `BOOKORBIT_RESET_CONFIRM=yes bookorbit-db-reset` in its terminal. The command refuses to operate if the configured database URL is not the workspace-private Coder database.

> [!IMPORTANT]
> This is a development environment. The PostgreSQL password and the values copied from BookOrbit's example environment file are intentionally development-only credentials.

> [!TIP]
> To switch the existing checkout to another fork, update its Git remote inside the workspace. The repository parameter controls the first clone and is immutable after workspace creation.
