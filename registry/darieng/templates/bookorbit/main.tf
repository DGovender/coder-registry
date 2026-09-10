terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "docker_socket" {
  type        = string
  default     = ""
  description = "Optional Docker socket URI. Uses the provisioner's default Docker socket when empty."
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "repository_url" {
  name         = "repository_url"
  display_name = "BookOrbit repository"
  description  = "Git URL cloned into the workspace. Use your BookOrbit fork to contribute changes."
  type         = "string"
  default      = "https://github.com/DGovender/bookorbit.git"
  mutable      = false
  validation {
    # Coder's web form evaluates this with JavaScript RegExp, which does not
    # support POSIX classes such as [[:space:]]. Terraform's RE2 and JS both
    # support \s, so keep this expression portable between the CLI and UI.
    regex = "^https://[^\\s]+$"
    error = "Enter an HTTPS Git repository URL."
  }
}

locals {
  home_dir                = "/home/node"
  workspace_dir           = "${local.home_dir}/bookorbit"
  database_host           = "postgres"
  database_url            = "postgres://bookorbit:bookorbit@${local.database_host}:5432/bookorbit"
  workspace_name          = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  database_name           = "${local.workspace_name}-postgres"
  network_name            = "coder-${data.coder_workspace.me.id}-bookorbit"
  git_author_name         = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email        = data.coder_workspace_owner.me.email
  wildcard_access_url     = "https://*.dev.darieng.com"
  bookorbit_app_subdomain = "bookorbit--${lower(data.coder_workspace.me.name)}--${lower(data.coder_workspace_owner.me.name)}"
  bookorbit_app_url       = replace(local.wildcard_access_url, "*", local.bookorbit_app_subdomain)
  setup_script     = <<-EOT
    set -euo pipefail

    cd "${local.workspace_dir}"
    if [ ! -f server/.env ]; then
      cp server/.env.example server/.env
    fi

    set_env_value() {
      local key="$1"
      local value="$2"
      local env_file="server/.env"
      local env_tmp
      env_tmp="$(mktemp)"

      awk -v key="$key" -v value="$value" '
        index($0, key "=") == 1 {
          if (!replaced++) print key "=" value
          next
        }
        { print }
        END {
          if (!replaced) print key "=" value
        }
      ' "$env_file" > "$env_tmp"
      mv "$env_tmp" "$env_file"
    }

    # These values deliberately keep a Coder workspace on its private dev database.
    set_env_value DATABASE_URL "${local.database_url}"
    set_env_value NODE_ENV development
    set_env_value APP_DATA_PATH ../local/data
    set_env_value APP_URL "${local.bookorbit_app_url}"
    set_env_value CLIENT_URL "${local.bookorbit_app_url}"

    pnpm install --frozen-lockfile

    until pg_isready --host="${local.database_host}" --username=bookorbit --dbname=bookorbit >/dev/null 2>&1; do
      sleep 2
    done

    pnpm db:migrate

    if ! pgrep -u "$USER" -f '[p]npm dev' >/dev/null 2>&1; then
      nohup pnpm dev > "$HOME/.bookorbit-dev.log" 2>&1 &
    fi
  EOT
}

resource "docker_image" "workspace" {
  name = "coder-bookorbit:node24"
  build {
    context = "${path.module}/build"
  }
}

resource "docker_network" "bookorbit" {
  count = data.coder_workspace.me.start_count
  name  = local.network_name
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "docker_volume" "database" {
  name = "coder-${data.coder_workspace.me.id}-bookorbit-postgres"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "docker_container" "database" {
  count = data.coder_workspace.me.start_count
  image = "pgvector/pgvector:pg18"
  name  = local.database_name
  env = [
    "POSTGRES_USER=bookorbit",
    "POSTGRES_PASSWORD=bookorbit",
    "POSTGRES_DB=bookorbit",
  ]

  networks_advanced {
    name    = docker_network.bookorbit[0].name
    aliases = [local.database_host]
  }

  volumes {
    container_path = "/var/lib/postgresql"
    volume_name    = docker_volume.database.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = docker_image.workspace.name
  name       = local.workspace_name
  hostname   = data.coder_workspace.me.name
  user       = "node"
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  networks_advanced {
    name = docker_network.bookorbit[0].name
  }

  volumes {
    container_path = local.home_dir
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }

  depends_on = [docker_container.database]
}

module "git_clone" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/coder/git-clone/coder"
  version           = "2.0.3"
  agent_id          = coder_agent.main.id
  url               = data.coder_parameter.repository_url.value
  base_dir          = local.home_dir
  folder_name       = "bookorbit"
  post_clone_script = local.setup_script
}

module "vscode_web" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/vscode-web/coder"
  version         = "1.6.2"
  agent_id        = coder_agent.main.id
  folder          = local.workspace_dir
  accept_license  = true
  telemetry_level = "off"
  install_prefix  = "${local.home_dir}/.local/vscode-web"
  use_cached      = true
  order           = 1
  extensions      = ["dbaeumer.vscode-eslint", "esbenp.prettier-vscode"]
}

module "zed" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.5"
  agent_id = coder_agent.main.id
  folder   = local.workspace_dir
  order    = 2
}

module "codex" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/codex/coder"
  version  = "5.4.0"
  agent_id = coder_agent.main.id
  workdir  = local.workspace_dir
}

resource "coder_app" "bookorbit" {
  agent_id     = coder_agent.main.id
  slug         = "bookorbit"
  display_name = "BookOrbit"
  url          = "http://localhost:5173"
  icon         = "/emojis/1f4da.png"
  share        = "owner"
  subdomain    = true
  order        = 3

  healthcheck {
    url       = "http://localhost:5173"
    interval  = 5
    threshold = 12
  }
}
