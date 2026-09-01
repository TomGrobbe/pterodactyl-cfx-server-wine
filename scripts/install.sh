#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

trap 'echo "!!! install failed on line ${LINENO}"' ERR

DEPOT_BASE="https://depot.cfx.re/public/p/fxserver_gen9/u"
ARTIFACT="cfx-server_win_x64.zip"
SERVER_DATA_URL="https://github.com/citizenfx/cfx-server-data/archive/refs/heads/master.zip"
SERVER_DIR="/mnt/server"

CFX_CHANNEL="${CFX_CHANNEL:-main}"
CORECLR_CHANNEL="${CORECLR_CHANNEL:-csharp_improvements}"
DOWNLOAD_SERVER_DATA="${DOWNLOAD_SERVER_DATA:-1}"
LICENSE_KEY="${LICENSE_KEY:-}"
SERVER_PORT="${SERVER_PORT:-30120}"
SCRIPT_REVISION="2026-09-01.4"

mkdir -p "${SERVER_DIR}"
exec > >(tee -a "${SERVER_DIR}/install.log") 2>&1

echo "==> cfx installer revision ${SCRIPT_REVISION}"
echo "==> container: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')"
echo "==> running as uid $(id -u), target ${SERVER_DIR}"
echo "==> channels: ${CFX_CHANNEL} and ${CORECLR_CHANNEL}"
df -h "${SERVER_DIR}" || true

MISSING=""
for tool in curl jq unzip; do
    command -v "${tool}" > /dev/null 2>&1 || MISSING="${MISSING} ${tool}"
done

if [ -n "${MISSING}" ]; then
    echo "==> installing missing tools:${MISSING}"
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates ${MISSING} > /dev/null
else
    echo "==> curl, jq and unzip are already present"
fi

cd "${SERVER_DIR}"

WORK="$(mktemp -d -p "${SERVER_DIR}" .cfx-install.XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

BUILD_NUMBER=""

download_channel() {
    local channel="$1"
    local destination="$2"
    local manifest url sha256

    echo "==> reading depot channel '${channel}'"
    if ! manifest="$(curl -fsSL --retry 3 --retry-delay 5 "${DEPOT_BASE}/${channel}")"; then
        echo "!!! could not read ${DEPOT_BASE}/${channel}"
        exit 1
    fi

    BUILD_NUMBER="$(jq -r '.build // empty' <<< "${manifest}")"
    url="$(jq -r --arg f "${ARTIFACT}" '.content_files[]? | select(.relative_path == $f) | .download_url' <<< "${manifest}")"
    sha256="$(jq -r --arg f "${ARTIFACT}" '.content_files[]? | select(.relative_path == $f) | .hash_sha256' <<< "${manifest}")"

    if [ -z "${url}" ]; then
        echo "!!! channel '${channel}' does not publish ${ARTIFACT}"
        exit 1
    fi

    echo "==> downloading ${ARTIFACT} from '${channel}' (build ${BUILD_NUMBER:-unknown})"
    curl -fL --retry 3 --retry-delay 5 --progress-bar -o "${destination}" "${url}"

    if [ -n "${sha256}" ]; then
        echo "${sha256}  ${destination}" | sha256sum -c -
    else
        echo "--- depot published no checksum, skipping verification"
    fi
}

download_channel "${CFX_CHANNEL}" "${WORK}/base.zip"
BASE_BUILD="${BUILD_NUMBER}"

echo "==> installing server binaries"
rm -rf "${SERVER_DIR}/coreclr_server" "${SERVER_DIR}/system_resources"
unzip -oq "${WORK}/base.zip" -d "${SERVER_DIR}"
rm -f "${WORK}/base.zip"

download_channel "${CORECLR_CHANNEL}" "${WORK}/coreclr.zip"
CORECLR_BUILD="${BUILD_NUMBER}"

echo "==> replacing coreclr_server from '${CORECLR_CHANNEL}'"
rm -rf "${SERVER_DIR}/coreclr_server"
unzip -oq "${WORK}/coreclr.zip" 'coreclr_server/*' -d "${SERVER_DIR}"
rm -f "${WORK}/coreclr.zip"

if [ ! -x "${SERVER_DIR}/cfx-server.exe" ] && [ ! -f "${SERVER_DIR}/cfx-server.exe" ]; then
    echo "!!! cfx-server.exe is missing after extraction"
    exit 1
fi

if [ ! -f "${SERVER_DIR}/coreclr_server/CitizenFX.Host.Server.dll" ]; then
    echo "!!! coreclr_server looks incomplete after extraction"
    exit 1
fi

if [ "${DOWNLOAD_SERVER_DATA}" = "1" ] && [ ! -d "${SERVER_DIR}/resources" ]; then
    echo "==> downloading cfx-server-data resources"
    curl -fL --retry 3 --retry-delay 5 --progress-bar -o "${WORK}/server-data.zip" "${SERVER_DATA_URL}"
    unzip -oq "${WORK}/server-data.zip" -d "${WORK}/server-data"
    mv "${WORK}/server-data/cfx-server-data-master/resources" "${SERVER_DIR}/resources"
    rm -rf "${WORK}/server-data.zip" "${WORK}/server-data"
fi

mkdir -p "${SERVER_DIR}/resources"

if [ ! -f "${SERVER_DIR}/server.cfg" ]; then
    echo "==> writing a starter server.cfg"
    cat > "${SERVER_DIR}/server.cfg" <<CFG
endpoint_add_tcp "0.0.0.0:${SERVER_PORT}"
endpoint_add_udp "0.0.0.0:${SERVER_PORT}"

ensure chat
ensure mapmanager
ensure spawnmanager
ensure baseevents
ensure basic-gamemode
ensure playernames
ensure fivem-map-skater

sv_hostname "New Cfx Server"
sets sv_projectName "New Cfx Server"
sets sv_projectDesc "A Cfx Enhanced server running on Wine"

sv_maxclients 48
sv_scriptHookAllowed 0

sv_licenseKey "${LICENSE_KEY}"
CFG
fi

printf 'base %s (build %s), coreclr %s (build %s)\n' \
    "${CFX_CHANNEL}" "${BASE_BUILD:-unknown}" \
    "${CORECLR_CHANNEL}" "${CORECLR_BUILD:-unknown}" > "${SERVER_DIR}/.cfx-build"

echo "==> done: $(cat "${SERVER_DIR}/.cfx-build")"
echo "==> install finished, contents of ${SERVER_DIR}"
ls -la "${SERVER_DIR}"
