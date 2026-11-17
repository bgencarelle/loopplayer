#!/bin/bash
# Double-click: pick the folder the playlist is built from.
# Picking a different folder starts that folder's playlist from the beginning.
cd "$(dirname "$0")" || exit 1
DIR=$(osascript -e 'POSIX path of (choose folder with prompt "Choose the folder with the videos to loop:")' 2>/dev/null)
if [ -z "$DIR" ]; then echo "No folder chosen - nothing changed."; sleep 2; exit 0; fi
DIR="${DIR%/}"
./loopplayer.sh set VIDEO_FOLDER "$DIR"
./loopplayer.sh restart
echo "Now playing from: $DIR"
sleep 3
