#!/bin/bash

cd /home/container || exit 1

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

if [ ! -d "${WINEPREFIX}" ]; then
    printf "${YELLOW}First boot: building the wine prefix, this takes a moment.${RESET}\n"
    wineboot --init >/dev/null 2>&1
    wineserver --wait
    printf "${GREEN}wine prefix ready.${RESET}\n"
fi

MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

printf ":/home/container$ %s\n" "${MODIFIED_STARTUP}"

eval ${MODIFIED_STARTUP}
