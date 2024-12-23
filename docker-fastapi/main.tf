# TODO: Add docker max cpu/ram

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

locals {
  username = data.coder_workspace_owner.me.name
}

data "coder_parameter" "REPO" {
  name        = "Repository URL"
  type        = "string"
  description = "Git repository to fetch"
}

data "coder_parameter" "FOLDER" {
  name        = "Working directory"
  type        = "string"
  default     = "src"
  description = "Folder contains code"
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {

}

data "coder_workspace_owner" "me" {
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      git clone ${data.coder_parameter.REPO.value} "/home/${local.username}/${data.coder_parameter.FOLDER.value}"
      sed -i -e \
        's/\"path\": \"\/home\/coder\/src\"/\"path\": \"\/home\/${local.username}\/${data.coder_parameter.FOLDER.value}\"/g' \
        /home/${local.username}/fastapi.code-workspace
      sed -i -e \
        's/\"name\": \"src\"/\"name\": \"${data.coder_parameter.FOLDER.value}\"/g' \
        /home/${local.username}/fastapi.code-workspace
      touch ~/.init_done
    fi

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.19.1
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
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
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "Code Server"
  url          = "http://localhost:13337/?workspace=/home/${local.username}/fastapi.code-workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "docker_network" "private_network" {
  name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-internal"
}

# See https://registry.coder.com/modules/jetbrains-gateway
module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/jetbrains-gateway/coder"

  # JetBrains IDEs to make available for the user to select
  jetbrains_ides = ["IU", "PY", "WS", "PS", "RD", "CL", "GO", "RM"]
  default        = "PY"

  # Default folder to open when starting a JetBrains IDE
  folder = "/home/coder"

  # This ensures that the latest version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = ">= 1.0.0"

  agent_id   = coder_agent.main.id
  agent_name = "main"
  order      = 2
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
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
    value = data.coder_workspace_owner.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "com.docker.compose.project"
    value = "coder"
  }
}

resource "docker_volume" "db_volume" {
  name = "coder-${data.coder_workspace_owner.me.id}-db"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
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
    value = data.coder_workspace_owner.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "com.docker.compose.project"
    value = "coder"
  }
}

resource "docker_container" "database" {
  count = data.coder_workspace.me.start_count
  image = "postgres:16"
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-db"
  hostname = "${data.coder_workspace_owner.me.name}-db"
  env = [
    "POSTGRES_USER=${data.coder_workspace_owner.me.name}",
    "POSTGRES_PASSWORD=${data.coder_workspace_owner.me.name}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/var/lib/postgresql/data"
    volume_name    = docker_volume.db_volume.name
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
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "com.docker.compose.project"
    value = "coder"
  }

  networks_advanced {
    name    = docker_network.private_network.name
    aliases = ["postgres"]
  }
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace_owner.me.id}"
  build {
    context = "./build"
    build_args = {
      USER = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace_owner.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
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
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "com.docker.compose.project"
    value = "coder"
  }

  networks_advanced {
    name    = docker_network.private_network.name
    aliases = ["workspace"]
  }
}
