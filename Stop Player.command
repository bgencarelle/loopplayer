#!/bin/bash
# Double-click: stop playback so the video folder can be updated.
# The saved place is kept. Start again with "Start Player" (or just reboot).
PLIST="$HOME/Library/LaunchAgents/com.loopplayer.agent.plist"
launchctl unload "$PLIST" 2>/dev/null
sleep 2
pkill -f "http-port=48765" 2>/dev/null
echo "LoopPlayer stopped. You can now add, remove or rename videos."
echo "When you're done, double-click \"Start Player\"."
sleep 4
