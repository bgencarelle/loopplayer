#!/bin/bash
# Double-click: show which video, where in it, and how many loops so far.
cd "$(dirname "$0")" && ./loopplayer.sh status
echo; read -n 1 -s -r -p "Press any key to close."
