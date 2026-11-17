#!/bin/bash
# Double-click: stop LoopPlayer and remove the login item. Videos are kept.
PLIST="$HOME/Library/LaunchAgents/com.loopplayer.agent.plist"
launchctl unload -w "$PLIST" 2>/dev/null
rm -f "$PLIST"
for apps in /Applications "$HOME/Applications"; do
    [ -L "$apps/LoopPlayer" ] && rm -f "$apps/LoopPlayer"
done
pkill -f "http-port=48765" 2>/dev/null
echo "LoopPlayer stopped and removed from login. Your videos and saved position are still in ~/LoopPlayer."
read -n 1 -s -r -p "Press any key to close."
