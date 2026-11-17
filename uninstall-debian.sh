#!/bin/bash
# Stop LoopPlayer and remove it from login. Videos, settings and the saved
# place in ~/LoopPlayer are kept.
systemctl --user stop loopplayer.service 2>/dev/null
pkill -f "http-port=48765" 2>/dev/null
rm -f "$HOME/.config/systemd/user/loopplayer.service" \
      "$HOME/.config/autostart/loopplayer.desktop" \
      "$HOME/.local/share/applications/loopplayer-"*.desktop
systemctl --user daemon-reload 2>/dev/null
# remove LoopPlayer's KDE window rule (other rules are kept)
KW=kwriteconfig6; command -v $KW >/dev/null || KW=kwriteconfig5
KR=kreadconfig6; command -v $KR >/dev/null || KR=kreadconfig5
if command -v $KW >/dev/null && command -v $KR >/dev/null; then
    rules=$($KR --file kwinrulesrc --group General --key rules 2>/dev/null | tr ',' '\n' | grep -vx loopplayer-vlc | paste -sd, -)
    $KW --file kwinrulesrc --group General --key rules "$rules"
    $KW --file kwinrulesrc --group General --key count "$(printf '%s' "$rules" | tr ',' '\n' | grep -c .)"
    $KW --file kwinrulesrc --group loopplayer-vlc --key wmclass --delete
    for q in qdbus6 qdbus qdbus-qt5; do
        command -v $q >/dev/null && { $q org.kde.KWin /KWin reconfigure >/dev/null 2>&1; break; }
    done
fi
echo "LoopPlayer stopped and removed from login. ~/LoopPlayer is untouched."
echo "(Automatic login, screen-blanking and other desktop settings were left as they are.)"
