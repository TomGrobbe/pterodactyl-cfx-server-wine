#!/bin/bash

cd /home/container || exit 1

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

printf "${GREEN}wine:${RESET} %s\n" "$(wine --version 2>/dev/null || echo 'unavailable')"

if [ -f .cfx-build ]; then
    printf "${GREEN}cfx:${RESET}  %s\n" "$(cat .cfx-build)"
fi

if [ "${XVFB}" = "1" ]; then
    printf "${GREEN}xvfb:${RESET} starting on ${DISPLAY}\n"
    Xvfb "${DISPLAY}" -screen 0 "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH}" &
else
    unset DISPLAY
fi

MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
EXPANDED_STARTUP=$(eval echo "${MODIFIED_STARTUP}" 2>/dev/null)
TARGET_EXE=$(printf '%s\n' "${EXPANDED_STARTUP}" | grep -oiE '[^[:space:]]+[.]exe' | head -1)

if [ -z "${TARGET_EXE}" ]; then
    printf "${RED}!!! the startup command has no .exe left once the panel filled in its variables${RESET}\n"
    printf "${RED}!!! it came out as: %s${RESET}\n" "${EXPANDED_STARTUP}"
    printf "${RED}!!! set the startup command to: wine cfx-server.exe +exec server.cfg${RESET}\n"
elif [ ! -f "${TARGET_EXE}" ]; then
    printf "${RED}!!! %s is not in /home/container${RESET}\n" "${TARGET_EXE}"
    printf "${RED}!!! the install did not finish, reinstall the server and read install.log${RESET}\n"
    exit 1
fi

if [ ! -s server.cfg ]; then
    printf "${YELLOW}server.cfg is missing or empty, the server will not start properly.${RESET}\n"
    printf "${YELLOW}Reinstall the server to have one written for you.${RESET}\n"
fi

if [ ! -d "${WINEPREFIX}" ]; then
    printf "${YELLOW}First boot: building the wine prefix, this takes a moment.${RESET}\n"
    wineboot --init >/dev/null 2>&1
    wineserver --wait
    printf "${GREEN}wine prefix ready.${RESET}\n"
fi

printf ":/home/container$ %s\n" "${MODIFIED_STARTUP}"

eval ${MODIFIED_STARTUP}
