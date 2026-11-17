#!/bin/bash
# Double-click: start playback again after updating the video folder.
# New videos go on the end of the playlist; it resumes where it stopped.
PLIST="$HOME/Library/LaunchAgents/com.loopplayer.agent.plist"
if [ ! -f "$PLIST" ]; then echo "LoopPlayer isn't installed - run Install.command first."; sleep 4; exit 1; fi
launchctl unload "$PLIST" 2>/dev/null
launchctl load "$PLIST"
echo "LoopPlayer started."
sleep 3
