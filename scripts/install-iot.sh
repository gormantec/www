#!/bin/sh
# =============================================================================
# docker-iot installer — Alpine Linux from scratch
# =============================================================================
# curl -fsSL https://www.gormantec.com/scripts/install.sh | sh
#
# Idempotent — safe to run multiple times. Checks each step and skips if done.
# =============================================================================
set -e

if [ -t 1 ]; then
    RED="$(printf '\033[0;31m')"
    GREEN="$(printf '\033[0;32m')"
    YELLOW="$(printf '\033[1;33m')"
    CYAN="$(printf '\033[0;36m')"
    NC="$(printf '\033[0m')"
else
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    NC=""
fi

echo ""
echo "${CYAN}============================================${NC}"
echo "${CYAN}   docker-iot Installer${NC}"
echo "${CYAN}============================================${NC}"
echo ""

# ── Check Alpine ────────────────────────────────────────────────
if [ ! -f /etc/alpine-release ]; then
    echo "${RED}This installer is for Alpine Linux only.${NC}"
    exit 1
fi
echo "${GREEN}✓${NC} Alpine Linux $(cat /etc/alpine-release)"

# ── Helper: prompt with default ─────────────────────────────────
if [ -t 0 ]; then
    PROMPT_FD=0
elif [ -r /dev/tty ]; then
    exec 3</dev/tty
    PROMPT_FD=3
else
    PROMPT_FD=0
fi

ask() {
    prompt="$1"
    default="$2"
    secret="$3"
    value=""
    display_default=""

    if [ -n "$default" ]; then
        if [ "$secret" = "secret" ]; then
            display_default="*****"
        else
            display_default="$default"
        fi
        printf "${CYAN}%s [%s]:${NC} " "$prompt" "$display_default" >&$PROMPT_FD
    else
        printf "${CYAN}%s:${NC} " "$prompt" >&$PROMPT_FD
    fi

    if [ "$secret" = "secret" ]; then
        if [ -t "$PROMPT_FD" ]; then
            stty -echo <&$PROMPT_FD 2>/dev/null || true
        fi
        read -r value <&$PROMPT_FD
        if [ -t "$PROMPT_FD" ]; then
            stty echo <&$PROMPT_FD 2>/dev/null || true
        fi
        if [ -n "$value" ] || [ -n "$default" ]; then
            printf "*****\n" >&$PROMPT_FD
        else
            printf "\n" >&$PROMPT_FD
        fi
    else
        read -r value <&$PROMPT_FD
    fi

    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi
    echo "$value"
}

# ── Helper: check if a step is already done ─────────────────────
already() {
    echo "  ${YELLOW}⏭${NC}  $1 (already done)"
}

json_get_value() {
    key="$1"
    printf '%s\n' "$ENV_JSON" | awk -v key="$key" '
        {
            # Object format: "ROOT_DOMAIN": "gormantec.com"
            if (match($0, "^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*\"")) {
                line = $0
                sub("^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*\"", "", line)
                sub("\".*$", "", line)
                print line
                exit
            }

            # Array format entry start: "Name": "ROOT_DOMAIN"
            if (match($0, "^[[:space:]]*\"Name\"[[:space:]]*:[[:space:]]*\"" key "\"")) {
                in_entry = 1
                next
            }

            # Array format value line: "Value": "gormantec.com"
            if (in_entry && match($0, "^[[:space:]]*\"Value\"[[:space:]]*:[[:space:]]*\"")) {
                line = $0
                sub("^[[:space:]]*\"Value\"[[:space:]]*:[[:space:]]*\"", "", line)
                sub("\".*$", "", line)
                print line
                exit
            }

            # End of object without a Value means malformed entry; reset state.
            if (in_entry && $0 ~ /^[[:space:]]*}[[:space:]]*,?[[:space:]]*$/) {
                in_entry = 0
            }
        }
    '
}

sanitize_loaded_default() {
    key="$1"
    value="$2"
    placeholder_plain="\$$key"
    placeholder_braced="\${$key}"

    case "$value" in
        ""|"null"|"undefined"|"$key"|"$placeholder_plain"|"$placeholder_braced")
            echo ""
            ;;
        *)
            echo "$value"
            ;;
    esac
}

ENV_FILE="/var/lib/docker/volumes/docker-iot-data/_data/env.json"

load_existing_env() {
    ENV_JSON=""
    if [ -f "$ENV_FILE" ]; then
        ENV_JSON="$(cat "$ENV_FILE")"
        return
    fi

    if command -v docker >/dev/null 2>&1 && docker volume inspect docker-iot-data >/dev/null 2>&1; then
        mountpoint="$(docker volume inspect docker-iot-data --format '{{.Mountpoint}}' 2>/dev/null || true)"
        if [ -n "$mountpoint" ] && [ -f "$mountpoint/env.json" ]; then
            ENV_JSON="$(cat "$mountpoint/env.json")"
            return
        fi
        ENV_JSON="$(docker run --rm -i -v docker-iot-data:/data alpine cat /data/env.json 2>/dev/null || true)"
    fi
}

# ── 1. Install Docker ───────────────────────────────────────────
echo ""
echo "${CYAN}── 1. Docker${NC}"

if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        already "Docker $(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1)"
        already "Docker daemon operational"
    else
        echo "  Docker CLI is installed, but daemon is not fully operational. Verifying configuration..."
        apk add --no-cache docker docker-compose openrc cifs-utils iptables bridge
        rc-update add docker boot
        rc-service docker start
        echo "  ${GREEN}✓${NC} Docker started"
    fi
    # Ensure runtime deps are present even if Docker was installed without them
    for pkg in cifs-utils iptables bridge; do
        if ! apk info -e "$pkg" >/dev/null 2>&1; then
            apk add --no-cache "$pkg"
            echo "  ${GREEN}✓${NC} $pkg installed"
        fi
    done
else
    echo "  Installing Docker and dependencies..."
    apk add --no-cache docker docker-compose openrc cifs-utils iptables bridge
    rc-update add docker boot
    rc-service docker start
    echo "  ${GREEN}✓${NC} Docker installed"
fi

# ── 2. Docker daemon config ─────────────────────────────────────
echo ""
echo "${CYAN}── 2. Docker daemon${NC}"

DAEMON_JSON="/etc/docker/daemon.json"
if [ -f "$DAEMON_JSON" ]; then
    already "daemon.json exists"
elif docker info >/dev/null 2>&1; then
    already "Docker daemon operational (no daemon.json required)"
else
    mkdir -p "$(dirname "$DAEMON_JSON")"
    echo '{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "storage-driver": "overlay2"
}' > "$DAEMON_JSON"
    rc-service docker restart 2>/dev/null || service docker restart 2>/dev/null || true
    echo "  ${GREEN}✓${NC} Docker daemon configured"
fi

# ── 3. Docker Swarm ─────────────────────────────────────────────
echo ""
echo "${CYAN}── 3. Docker Swarm${NC}"

if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q 'active'; then
    already "Swarm active"
else
    echo "  Initialising Swarm..."
    docker swarm init 2>/dev/null || {
        echo "  ${YELLOW}⚠${NC}  Could not init Swarm (check network interfaces)"
    }
    echo "  ${GREEN}✓${NC} Docker Swarm initialised"
fi

# ── 4. Create docker user ───────────────────────────────────────
echo ""
echo "${CYAN}── 4. User 'docker'${NC}"

if id docker >/dev/null 2>&1; then
    already "User 'docker' exists"
else
    echo "  Creating user 'docker'..."
    adduser -D -g "Docker IoT" docker
    echo "  ${GREEN}✓${NC} User created"
fi

# Ensure docker user is in required groups
for grp in wheel audio video netdev docker; do
    if ! id docker | grep -q "$grp"; then
        addgroup docker "$grp" 2>/dev/null || adduser docker "$grp" 2>/dev/null || true
        echo "  ${GREEN}✓${NC} Added 'docker' to group '$grp'"
    fi
done

# Ensure docker group exists and user is in it
if ! getent group docker >/dev/null 2>&1; then
    addgroup docker 2>/dev/null || true
fi
adduser docker docker 2>/dev/null || true

load_existing_env

TUNNEL_TOKEN_DEFAULT="$(json_get_value 'TUNNEL_TOKEN')"
GITHUB_PAT_DEFAULT="$(json_get_value 'READ_PACKAGES_GITHUB_PAT')"
NAS_PASSWORD_DEFAULT="$(json_get_value 'DOCDB_NAS_PASSWORD')"
DOCDB_IOT_PASS_DEFAULT="$(json_get_value 'DOCDB_IOT_PASS')"
ROOT_DOMAIN_DEFAULT="$(json_get_value 'ROOT_DOMAIN')"
GATEKEEPER_SECRET_DEFAULT="$(json_get_value 'GATEKEEPER_SECRET')"
GITHUB_USERNAME_DEFAULT="$(json_get_value 'GITHUB_USERNAME')"
DEFAULT_NETWORK_DEFAULT="$(json_get_value 'DEFAULT_NETWORK')"
if [ -z "$DEFAULT_NETWORK_DEFAULT" ]; then
    DEFAULT_NETWORK_DEFAULT="$(json_get_value 'LAMBDA_NETWORK')"
fi
IMAGE_NAME_DEFAULT="$(json_get_value 'IMAGE_NAME')"
MQTT_HOST_DEFAULT="$(json_get_value 'MQTT_HOST')"
MQTT_PORT_DEFAULT="$(json_get_value 'MQTT_PORT')"
HTTP_PORT_DEFAULT="$(json_get_value 'HTTP_PORT')"
DOCDB_NAS_SERVER_DEFAULT="$(json_get_value 'DOCDB_NAS_SERVER')"
DOCDB_NAS_ROOT_DEFAULT="$(json_get_value 'DOCDB_NAS_ROOT')"
DOCDB_NAS_PROTOCOL_DEFAULT="$(json_get_value 'DOCDB_NAS_PROTOCOL')"
DOCDB_NAS_USERNAME_DEFAULT="$(json_get_value 'DOCDB_NAS_USERNAME')"

TUNNEL_TOKEN_DEFAULT="$(sanitize_loaded_default 'TUNNEL_TOKEN' "$TUNNEL_TOKEN_DEFAULT")"
GITHUB_PAT_DEFAULT="$(sanitize_loaded_default 'READ_PACKAGES_GITHUB_PAT' "$GITHUB_PAT_DEFAULT")"
NAS_PASSWORD_DEFAULT="$(sanitize_loaded_default 'DOCDB_NAS_PASSWORD' "$NAS_PASSWORD_DEFAULT")"
DOCDB_IOT_PASS_DEFAULT="$(sanitize_loaded_default 'DOCDB_IOT_PASS' "$DOCDB_IOT_PASS_DEFAULT")"
ROOT_DOMAIN_DEFAULT="$(sanitize_loaded_default 'ROOT_DOMAIN' "$ROOT_DOMAIN_DEFAULT")"
GATEKEEPER_SECRET_DEFAULT="$(sanitize_loaded_default 'GATEKEEPER_SECRET' "$GATEKEEPER_SECRET_DEFAULT")"
GITHUB_USERNAME_DEFAULT="$(sanitize_loaded_default 'GITHUB_USERNAME' "$GITHUB_USERNAME_DEFAULT")"
DEFAULT_NETWORK_DEFAULT="$(sanitize_loaded_default 'DEFAULT_NETWORK' "$DEFAULT_NETWORK_DEFAULT")"
if [ -z "$DEFAULT_NETWORK_DEFAULT" ]; then
    DEFAULT_NETWORK_DEFAULT="$(sanitize_loaded_default 'LAMBDA_NETWORK' "$(json_get_value 'LAMBDA_NETWORK')")"
fi
IMAGE_NAME_DEFAULT="$(sanitize_loaded_default 'IMAGE_NAME' "$IMAGE_NAME_DEFAULT")"
MQTT_HOST_DEFAULT="$(sanitize_loaded_default 'MQTT_HOST' "$MQTT_HOST_DEFAULT")"
MQTT_PORT_DEFAULT="$(sanitize_loaded_default 'MQTT_PORT' "$MQTT_PORT_DEFAULT")"
HTTP_PORT_DEFAULT="$(sanitize_loaded_default 'HTTP_PORT' "$HTTP_PORT_DEFAULT")"
DOCDB_NAS_SERVER_DEFAULT="$(sanitize_loaded_default 'DOCDB_NAS_SERVER' "$DOCDB_NAS_SERVER_DEFAULT")"
DOCDB_NAS_ROOT_DEFAULT="$(sanitize_loaded_default 'DOCDB_NAS_ROOT' "$DOCDB_NAS_ROOT_DEFAULT")"
DOCDB_NAS_PROTOCOL_DEFAULT="$(sanitize_loaded_default 'DOCDB_NAS_PROTOCOL' "$DOCDB_NAS_PROTOCOL_DEFAULT")"
DOCDB_NAS_USERNAME_DEFAULT="$(sanitize_loaded_default 'DOCDB_NAS_USERNAME' "$DOCDB_NAS_USERNAME_DEFAULT")"

if [ -z "$GATEKEEPER_SECRET_DEFAULT" ]; then
    GATEKEEPER_SECRET_DEFAULT=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c64)
fi

# ── 5. Collect secrets ──────────────────────────────────────────
echo ""
echo "${CYAN}── 5. Configuration${NC}"
echo "  Press Enter to accept defaults (shown in brackets)."
echo "  Required fields (no default) must be filled."
echo ""

TUNNEL_TOKEN=""
while [ -z "$TUNNEL_TOKEN" ]; do
    TUNNEL_TOKEN=$(ask "Cloudflare Tunnel token" "$TUNNEL_TOKEN_DEFAULT" "secret")
    if [ -z "$TUNNEL_TOKEN" ]; then
        echo "  ${RED}⚠  Tunnel token is required${NC}"
    fi
done

GITHUB_PAT=""
while [ -z "$GITHUB_PAT" ]; do
    GITHUB_PAT=$(ask "GitHub PAT (read:packages)" "$GITHUB_PAT_DEFAULT" "secret")
    if [ -z "$GITHUB_PAT" ]; then
        echo "  ${RED}⚠  GitHub PAT is required${NC}"
    fi
done

NAS_PASSWORD=""
while [ -z "$NAS_PASSWORD" ]; do
    NAS_PASSWORD=$(ask "NAS password" "$NAS_PASSWORD_DEFAULT" "secret")
    if [ -z "$NAS_PASSWORD" ]; then
        echo "  ${RED}⚠  NAS password is required${NC}"
    fi
done

DOCDB_IOT_PASS=""
while [ -z "$DOCDB_IOT_PASS" ]; do
    DOCDB_IOT_PASS=$(ask "Internal DocDB password" "$DOCDB_IOT_PASS_DEFAULT" "secret")
    if [ -z "$DOCDB_IOT_PASS" ]; then
        echo "  ${RED}⚠  Internal DocDB password is required${NC}"
    fi
done

echo ""
ROOT_DOMAIN=$(ask "Root domain" "${ROOT_DOMAIN_DEFAULT:-gormantec.com}")
GATEKEEPER_SECRET=$(ask "Gatekeeper secret" "$GATEKEEPER_SECRET_DEFAULT" "secret")
GITHUB_USERNAME=$(ask "GitHub username" "${GITHUB_USERNAME_DEFAULT:-gormantec}")
MQTT_HOST_DEFAULT2="mqtt.$ROOT_DOMAIN"
MQTT_HOST=$(ask "MQTT host" "${MQTT_HOST_DEFAULT:-$MQTT_HOST_DEFAULT2}")
MQTT_PORT=$(ask "MQTT port" "${MQTT_PORT_DEFAULT:-8883}")
HTTP_PORT=$(ask "HTTP port" "${HTTP_PORT_DEFAULT:-9090}")
DEFAULT_NETWORK=$(ask "Default network" "${DEFAULT_NETWORK_DEFAULT:-iot-default-net}")
IMAGE_NAME=$(ask "Docker image name" "${IMAGE_NAME_DEFAULT:-gormantec/docker-iot}")
READ_PACKAGES_GITHUB_PAT="$GITHUB_PAT"

normalize_image_reference() {
    name="$1"
    case "$name" in
        *.*/*|*:*/*|localhost/*)
            prefix="$name"
            ;;
        *)
            prefix="ghcr.io/$name"
            ;;
    esac

    last_component=${prefix##*/}
    case "$last_component" in
        *@*|*:* )
            printf '%s' "$prefix"
            ;;
        *)
            printf '%s:latest' "$prefix"
            ;;
    esac
}

IMAGE_REF="$(normalize_image_reference "$IMAGE_NAME")"
DOCDB_NAS_SERVER=$(ask "NAS server hostname" "${DOCDB_NAS_SERVER_DEFAULT:-synologynas.local}")
DOCDB_NAS_ROOT=$(ask "NAS share root path" "${DOCDB_NAS_ROOT_DEFAULT:-/docker-iot/docker-share}")
DOCDB_NAS_PROTOCOL=$(ask "NAS protocol (cifs/nfs)" "${DOCDB_NAS_PROTOCOL_DEFAULT:-cifs}")
DOCDB_NAS_USERNAME=$(ask "NAS username" "${DOCDB_NAS_USERNAME_DEFAULT:-docker-iot}")

mask_secret() {
    printf '%s\n' "$1" | sed -E 's/^(.{6}).*(.{4})$/\1***************************\2/'
}

test_github_pat() {
    masked_pat=$(mask_secret "$GITHUB_PAT")
    echo "  Connecting to GitHub with PAT=\"$masked_pat\""
    login_output=$(printf '%s\n' "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin 2>&1)
    login_status=$?
    if [ "$login_status" -eq 0 ]; then
        echo "  ${GREEN}✓${NC} GitHub connection successful"
        return 0
    fi
    echo "  ${RED}✗${NC} GitHub PAT validation failed"
    printf '    %s\n' "$login_output"
    return 1
}

# ── Helper: GitHub Packages login ─────────────────────────────────
docker_login_ghcr() {
    if [ -n "$GITHUB_PAT" ] && [ -n "$GITHUB_USERNAME" ]; then
        if printf '%s\n' "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# ── 6. Deploy docker-iot ────────────────────────────────────────
echo ""
echo "${CYAN}── 6. Deploy docker-iot${NC}"

# Validate GitHub PAT before pulling image
if ! test_github_pat; then
    echo "  ${YELLOW}⚠${NC}  GitHub PAT validation failed. Image pull may also fail."
fi

# Pull image
echo "  Pulling ${IMAGE_REF}..."
if docker pull "${IMAGE_REF}"; then
    :
elif [ "${IMAGE_REF#ghcr.io/}" != "$IMAGE_REF" ] && docker_login_ghcr && docker pull "${IMAGE_REF}"; then
    :
else
    echo "  ${YELLOW}⚠${NC}  Could not pull image (check image name, GitHub PAT, GitHub username, and network)"
    echo "  Image will be pulled on first stack deploy."
fi

# Create env.json directly in the Docker volume mountpoint used by the service.
# This canonical host path maps to /usr/src/app/data/env.json inside the container.
VOLUME_NAME="docker-iot-data"
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    docker volume create "$VOLUME_NAME" >/dev/null
    echo "  ${GREEN}✓${NC} Docker volume '$VOLUME_NAME' created"
fi

mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << ENVEOF
[
    { "Name": "ROOT_DOMAIN", "Value": "$ROOT_DOMAIN" },
    { "Name": "TUNNEL_TOKEN", "Value": "$TUNNEL_TOKEN" },
    { "Name": "READ_PACKAGES_GITHUB_PAT", "Value": "$GITHUB_PAT" },
    { "Name": "GITHUB_USERNAME", "Value": "$GITHUB_USERNAME" },
    { "Name": "DEFAULT_NETWORK", "Value": "$DEFAULT_NETWORK" },
    { "Name": "IMAGE_NAME", "Value": "$IMAGE_NAME" },
    { "Name": "DOCDB_NAS_SERVER", "Value": "$DOCDB_NAS_SERVER" },
    { "Name": "DOCDB_NAS_ROOT", "Value": "$DOCDB_NAS_ROOT" },
    { "Name": "DOCDB_NAS_PROTOCOL", "Value": "$DOCDB_NAS_PROTOCOL" },
    { "Name": "DOCDB_NAS_USERNAME", "Value": "$DOCDB_NAS_USERNAME" },
    { "Name": "DOCDB_NAS_PASSWORD", "Value": "$NAS_PASSWORD" },
    { "Name": "DOCDB_IOT_PASS", "Value": "$DOCDB_IOT_PASS" },
    { "Name": "GATEKEEPER_SECRET", "Value": "$GATEKEEPER_SECRET" }
]
ENVEOF

chmod 600 "$ENV_FILE" 2>/dev/null || true
echo "  ${GREEN}✓${NC} env.json written to $ENV_FILE"

echo "  ${YELLOW}⚠${NC}  env.json is still required until tenant secrets are confirmed in Secrets Manager"

sanitize_compose_yaml_for_stack() {
    input_file="$1"
    output_file="$2"

    awk '
        function leading_spaces(s, n) {
            n = match(s, /[^ ]/)
            return n ? n - 1 : length(s)
        }
        {
            line = $0
            indent = leading_spaces(line)
            trimmed = line
            sub(/^[ ]+/, "", trimmed)

            # docker stack deploy rejects top-level "name:" in some environments.
            if (indent == 0 && trimmed ~ /^name:[[:space:]]*/) {
                next
            }

            if (indent == 0) {
                in_services = (trimmed ~ /^services:[[:space:]]*$/)
            }

            # Track current service block under "services:".
            if (in_services && indent == 2 && trimmed ~ /^[A-Za-z0-9_.-]+:[[:space:]]*$/) {
                in_service_block = 1
            } else if (indent <= 2 && trimmed !~ /^services:[[:space:]]*$/) {
                in_service_block = 0
            }

            # docker stack deploy rejects service-level "name:".
            if (in_services && in_service_block && indent == 4 && trimmed ~ /^name:[[:space:]]*/) {
                next
            }

            print line
        }
    ' "$input_file" > "$output_file"
}

extract_compose_yaml_from_image() {
    local image="$1"
    local out="$2"
    local container
    container=$(docker create "$image" /bin/sh 2>/dev/null) || return 1
    if [ -z "$container" ]; then
        return 1
    fi

    local result=1
    local paths="/usr/src/app/compose.yaml /usr/src/app/docker-compose.yaml /compose.yaml /app/compose.yaml /docker-compose.yml /docker-compose.yaml /usr/src/app/docker-compose.yml"
    for path in $paths; do
        if docker cp "$container":"$path" "$out" >/dev/null 2>&1; then
            result=0
            break
        fi
    done

    docker rm -v "$container" >/dev/null 2>&1 || true
    return $result
}

# ── Deploy the stack ────────────────────────────────────────────
echo ""
echo "  Deploying docker-iot stack..."

# Export compose environment variables for docker stack deploy/docker compose
# These values are substituted by the compose file at deploy time.
echo "  Exporting compose environment variables..."
export TUNNEL_TOKEN
export ROOT_DOMAIN
export MQTT_HOST
export MQTT_PORT
export HTTP_PORT
export GATEKEEPER_SECRET
export READ_PACKAGES_GITHUB_PAT
export GITHUB_USERNAME
export DEFAULT_NETWORK
# Backward compatibility for older compose files still using LAMBDA_NETWORK.
LAMBDA_NETWORK="$DEFAULT_NETWORK"
export LAMBDA_NETWORK
export DOCDB_NAS_SERVER
export DOCDB_NAS_ROOT
export DOCDB_NAS_PROTOCOL
export DOCDB_NAS_USERNAME
DOCDB_NAS_PASSWORD="$NAS_PASSWORD"
export DOCDB_NAS_PASSWORD
export DOCDB_IOT_PASS

# Create overlay network for Lambda/ECS
if ! docker network ls --format '{{.Name}}' | grep -q "^${DEFAULT_NETWORK}$"; then
    docker network create --driver overlay --attachable "$DEFAULT_NETWORK" 2>/dev/null || true
    echo "  ${GREEN}✓${NC} Network '${DEFAULT_NETWORK}' created"
else
    already "Network '${DEFAULT_NETWORK}' exists"
fi

# Deploy using compose.yaml from the image, with env.json bind mount
COMPOSE_DIR="/opt/docker-iot"
mkdir -p "$COMPOSE_DIR"
COMPOSE_FILE="$COMPOSE_DIR/compose.yaml"
STACK_COMPOSE_FILE="$COMPOSE_DIR/compose.stack.yaml"

if extract_compose_yaml_from_image "$IMAGE_REF" "$COMPOSE_FILE"; then
    echo "  ${GREEN}✓${NC} compose.yaml extracted from image"
else
    echo "  ${RED}✗${NC} Could not extract compose.yaml from image"
    echo "    Checked candidate paths: /usr/src/app/compose.yaml /usr/src/app/docker-compose.yaml /compose.yaml /app/compose.yaml /docker-compose.yml /docker-compose.yaml /usr/src/app/docker-compose.yml"
fi

if [ ! -s "$COMPOSE_FILE" ]; then
    echo "  ${RED}✗${NC} No compose file available for deployment"
    exit 1
fi

sanitize_compose_yaml_for_stack "$COMPOSE_FILE" "$STACK_COMPOSE_FILE"
if [ ! -s "$STACK_COMPOSE_FILE" ]; then
    echo "  ${RED}✗${NC} Failed to sanitize compose file for stack deployment"
    exit 1
fi

if docker stack deploy -c "$STACK_COMPOSE_FILE" docker-iot; then
    echo "  ${GREEN}✓${NC} Stack deployed"
elif docker compose -f "$STACK_COMPOSE_FILE" up -d; then
    echo "  ${GREEN}✓${NC} Stack deployed via docker compose"
else
    echo "  ${RED}✗${NC} Stack deployment failed"
    exit 1
fi

# ── 7. Verify ────────────────────────────────────────────────────
echo ""
echo "${CYAN}── 7. Verify${NC}"

sleep 5
if docker ps --format '{{.Names}}' | grep -q 'docker-iot'; then
    echo "  ${GREEN}✓${NC} docker-iot container is running"
else
    echo "  ${YELLOW}⚠${NC}  Container may still be starting — check: docker ps"
fi

# ── Done ─────────────────────────────────────────────────────────
echo ""
echo "${GREEN}============================================${NC}"
echo "${GREEN}   docker-iot installed!${NC}"
echo "${GREEN}============================================${NC}"
echo ""
echo "  Configuration saved to: $ENV_FILE"
echo "  ${RED}IMPORTANT:${NC} This file will be deleted once DocDB is established."
echo "  Store these values securely before then."
echo ""
echo "  Useful commands:"
echo "    docker service ls          # List Swarm services"
echo "    docker stack ps docker-iot # Stack container status"
echo "    docker logs \$(docker ps -q --filter name=docker-iot)  # Server logs"
echo ""
echo "  Access the dashboard at your Cloudflare Tunnel URL."
echo ""
