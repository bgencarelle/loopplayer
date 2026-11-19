#!/bin/bash
# Double-click: pick the folder the playlist is built from.
# Picking a different folder starts that folder's playlist from the beginning.
cd "$(dirname "$0")" || exit 1
DIR=$(./loopplayer.sh pick-folder)
if [ -z "$DIR" ]; then echo "No folder chosen - nothing changed."; sleep 3; exit 0; fi
./loopplayer.sh set VIDEO_FOLDER "$DIR"
./loopplayer.sh restart
echo "Now playing from: $DIR  ($(./loopplayer.sh count-videos) videos found)"
sleep 4
