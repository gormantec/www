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
    printf '%s\n' "$ENV_JSON" | awk -v k="\"$key\"" '
        index($0, k) {
            line=$0
            sub(/.*:[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            print line
            exit
        }
    '
}

load_existing_env() {
    ENV_JSON=""
    env_file="/usr/src/app/data/env.json"
    if [ -f "$env_file" ]; then
        ENV_JSON="$(cat "$env_file")"
        return
    fi
    if command -v docker >/dev/null 2>&1 && docker volume inspect docker-iot-data >/dev/null 2>&1; then
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
ROOT_DOMAIN_DEFAULT="$(json_get_value 'ROOT_DOMAIN')"
GATEKEEPER_SECRET_DEFAULT="$(json_get_value 'GATEKEEPER_SECRET')"
GITHUB_USERNAME_DEFAULT="$(json_get_value 'GITHUB_USERNAME')"
LAMBDA_NETWORK_DEFAULT="$(json_get_value 'LAMBDA_NETWORK')"
IMAGE_NAME_DEFAULT="$(json_get_value 'IMAGE_NAME')"
DOCDB_NAS_SERVER_DEFAULT="$(json_get_value 'DOCDB_NAS_SERVER')"
DOCDB_NAS_ROOT_DEFAULT="$(json_get_value 'DOCDB_NAS_ROOT')"
DOCDB_NAS_PROTOCOL_DEFAULT="$(json_get_value 'DOCDB_NAS_PROTOCOL')"
DOCDB_NAS_USERNAME_DEFAULT="$(json_get_value 'DOCDB_NAS_USERNAME')"

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

echo ""
ROOT_DOMAIN=$(ask "Root domain" "${ROOT_DOMAIN_DEFAULT:-gormantec.com}")
GATEKEEPER_SECRET=$(ask "Gatekeeper secret" "$GATEKEEPER_SECRET_DEFAULT" "secret")
GITHUB_USERNAME=$(ask "GitHub username" "${GITHUB_USERNAME_DEFAULT:-gormantec}")
LAMBDA_NETWORK=$(ask "Lambda/ECS network" "${LAMBDA_NETWORK_DEFAULT:-iot-default-net}")
IMAGE_NAME=$(ask "Docker image name" "${IMAGE_NAME_DEFAULT:-gormantec/docker-iot}")

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

# ── 6. Deploy docker-iot ────────────────────────────────────────
echo ""
echo "${CYAN}── 6. Deploy docker-iot${NC}"

# Pull image
echo "  Pulling ${IMAGE_REF}..."
if docker pull "${IMAGE_REF}" >/dev/null 2>&1; then
    :
elif [ "${IMAGE_REF#ghcr.io/}" != "$IMAGE_REF" ] && docker_login_ghcr >/dev/null 2>&1 && docker pull "${IMAGE_REF}" >/dev/null 2>&1; then
    :
else
    echo "  ${YELLOW}⚠${NC}  Could not pull image (check image name, GitHub PAT, GitHub username, and network)"
    echo "  Image will be pulled on first stack deploy."
fi

# Create env.json in the Docker named volume used by the service.
# This ensures the container sees it at /usr/src/app/data/env.json.
VOLUME_NAME="docker-iot-data"
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    docker volume create "$VOLUME_NAME" >/dev/null
    echo "  ${GREEN}✓${NC} Docker volume '$VOLUME_NAME' created"
fi

docker run --rm -i -v "$VOLUME_NAME":/data alpine sh -c 'cat > /data/env.json' << ENVEOF
{
  "ROOT_DOMAIN": "$ROOT_DOMAIN",
  "TUNNEL_TOKEN": "$TUNNEL_TOKEN",
  "READ_PACKAGES_GITHUB_PAT": "$GITHUB_PAT",
  "GITHUB_USERNAME": "$GITHUB_USERNAME",
  "LAMBDA_NETWORK": "$LAMBDA_NETWORK",
  "IMAGE_NAME": "$IMAGE_NAME",
  "DOCDB_NAS_SERVER": "$DOCDB_NAS_SERVER",
  "DOCDB_NAS_ROOT": "$DOCDB_NAS_ROOT",
  "DOCDB_NAS_PROTOCOL": "$DOCDB_NAS_PROTOCOL",
  "DOCDB_NAS_USERNAME": "$DOCDB_NAS_USERNAME",
  "DOCDB_NAS_PASSWORD": "$NAS_PASSWORD",
  "GATEKEEPER_SECRET": "$GATEKEEPER_SECRET"
}
ENVEOF

docker run --rm -i -v "$VOLUME_NAME":/data alpine sh -c 'chmod 600 /data/env.json'
echo "  ${GREEN}✓${NC} env.json written to volume '$VOLUME_NAME'"

echo "  ${YELLOW}⚠${NC}  env.json is still required until tenant secrets are confirmed in Secrets Manager"

# ── Helper: GitHub Packages login ─────────────────────────────────
docker_login_ghcr() {
    if [ -n "$GITHUB_PAT" ] && [ -n "$GITHUB_USERNAME" ]; then
        if printf '%s\n' "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# ── Deploy the stack ────────────────────────────────────────────
echo ""
echo "  Deploying docker-iot stack..."

# Create overlay network for Lambda/ECS
if ! docker network ls --format '{{.Name}}' | grep -q "^${LAMBDA_NETWORK}$"; then
    docker network create --driver overlay --attachable "$LAMBDA_NETWORK" 2>/dev/null || true
    echo "  ${GREEN}✓${NC} Network '${LAMBDA_NETWORK}' created"
else
    already "Network '${LAMBDA_NETWORK}' exists"
fi

# Deploy using compose.yaml from the image, with env.json bind mount
# We use docker run first to extract the compose.yaml, then deploy as a stack
COMPOSE_DIR="/opt/docker-iot"
mkdir -p "$COMPOSE_DIR"

# Extract compose.yaml from the image
docker run --rm --entrypoint cat "${IMAGE_REF}" /usr/src/app/compose.yaml > "$COMPOSE_DIR/compose.yaml" 2>/dev/null || true

if [ ! -s "$COMPOSE_DIR/compose.yaml" ]; then
    # Fallback: use the installer's own compose.yaml if bundled
    echo "  ${YELLOW}⚠${NC}  Could not extract compose.yaml from image"
fi

# Deploy as Swarm stack
docker stack deploy -c "$COMPOSE_DIR/compose.yaml" docker-iot 2>/dev/null || {
    # If stack deploy fails, fall back to docker-compose
    echo "  ${YELLOW}⚠${NC}  Stack deploy failed — trying docker compose..."
    docker compose -f "$COMPOSE_DIR/compose.yaml" up -d 2>/dev/null || true
}
echo "  ${GREEN}✓${NC} Stack deployed"

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
