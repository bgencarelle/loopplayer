#!/bin/bash
# Double-click to install LoopPlayer for this user. Safe to run again.
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/LoopPlayer"
PLIST="$HOME/Library/LaunchAgents/com.loopplayer.agent.plist"

echo "== LoopPlayer install =="
VLCAPP=""
for a in /Applications/VLC.app "$HOME/Applications/VLC.app"; do
    [ -x "$a/Contents/MacOS/VLC" ] && { VLCAPP="$a"; break; }
done
if [ -z "$VLCAPP" ]; then
    echo "!! VLC was not found in /Applications. Install VLC first, then run this again."
    read -n 1 -s -r -p "Press any key to close."; exit 1
fi
VLCVER=$(defaults read "$VLCAPP/Contents/Info" CFBundleShortVersionString 2>/dev/null)
echo "Found VLC $VLCVER"
case "$VLCVER" in
    3.*) ;;
    *) echo "!! LoopPlayer is made for VLC 3.x. With VLC $VLCVER it may not start."
       echo "   Install VLC 3 if you can (it runs on OS X 10.7.5 and later)." ;;
esac

# stop a running copy before replacing its files
launchctl unload "$PLIST" 2>/dev/null
sleep 1

if [ "$SRC" != "$DEST" ]; then
    mkdir -p "$DEST"
    cp -f "$SRC/loopplayer.sh" "$SRC/"*.command "$SRC/README.txt" "$DEST/" 2>/dev/null
    [ -d "$SRC/media" ] && { mkdir -p "$DEST/media"; cp -n "$SRC/media/"* "$DEST/media/" 2>/dev/null; }
fi
mkdir -p "$DEST/media" "$DEST/state"
chmod +x "$DEST/loopplayer.sh" "$DEST/"*.command
xattr -d com.apple.quarantine "$DEST/"* 2>/dev/null
LP="$DEST/loopplayer.sh"

# ---- settings (asked only the first time; edit settings.txt later) ----
if [ ! -f "$DEST/settings.txt" ]; then
    echo
    echo "Which folder should the playlist come from?"
    echo "(Cancel the dialog to use $DEST/media)"
    DIR=$(osascript -e 'POSIX path of (choose folder with prompt "Choose the folder with the videos to loop:")' 2>/dev/null)
    DIR="${DIR%/}"; [ -z "$DIR" ] && DIR="$DEST/media"
    "$LP" set VIDEO_FOLDER "$DIR" >/dev/null
    echo "Video folder: $DIR"

    read -r -p "Show subtitles when a matching .srt file is in the folder? [Y/n] " yn
    case "$yn" in n|N) "$LP" set SUBTITLES no >/dev/null ;; *) "$LP" set SUBTITLES yes >/dev/null ;; esac

    "$LP" set FULLSCREEN yes >/dev/null
fi

mkdir -p "$HOME/Library/LaunchAgents"
# macOS 10.9 and later throttle the CPU and disk use of background jobs
# unless told otherwise, and VLC, started by this job, is throttled with it:
# the video stutters. "Interactive" = treat it like a normal app.
# (10.8 has no such throttling, and doesn't know the setting.)
PROCTYPE=""
OSMINOR=$(sw_vers -productVersion | awk -F. '{print ($1 > 10) ? 99 : $2}')
[ "${OSMINOR:-0}" -ge 9 ] && PROCTYPE="    <key>ProcessType</key><string>Interactive</string>"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.loopplayer.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DEST/loopplayer.sh</string>
        <string>run</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
$PROCTYPE
</dict>
</plist>
EOF

# ---- things that would otherwise pop up over the video (this user only) ----
# macOS: no "quit unexpectedly" dialogs, no screensaver, don't reopen apps
# and windows after a restart or power cut, don't offer new disks to Time Machine
defaults write com.apple.CrashReporter DialogType none
defaults -currentHost write com.apple.screensaver idleTime 0
# no password prompt if the screen ever does sleep (honoured up to macOS 10.12;
# on newer systems set it in System Preferences > Security & Privacy)
defaults write com.apple.screensaver askForPassword -int 0
defaults write com.apple.loginwindow TALLogoutSavesState -bool false
defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
# VLC: no update checks or "new version" window, no first-run question,
# no restoring of old windows
defaults write org.videolan.vlc SUEnableAutomaticChecks -bool false
defaults write org.videolan.vlc SUSendProfileInfo -bool false
defaults write org.videolan.vlc SUHasLaunchedBefore -bool true
defaults read org.videolan.vlc VLCFirstRun >/dev/null 2>&1 || \
    defaults write org.videolan.vlc VLCFirstRun -date "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
defaults write org.videolan.vlc ApplePersistenceIgnoreState -bool true
# VLC's own "continue playback?" off, so it never fights the script
VLCRC="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
if [ -f "$VLCRC" ]; then
    sed -i '' -e 's/^#*macosx-continue-playback=.*/macosx-continue-playback=2/' "$VLCRC"
fi

echo
echo "Recommended, needs an admin password. This Mac will:"
echo "  - never sleep or log out by itself, and switch back on after a power cut"
echo "  - restart by itself if the system freezes"
echo "  - stop checking for macOS updates (no update pop-ups)"
echo "  - not open the Bluetooth setup window when no keyboard or mouse is attached"
read -r -p "Do this now? [y/N] " yn
if [ "$yn" = y ] || [ "$yn" = Y ]; then
    # one command each, so one unsupported setting doesn't block the others
    sudo pmset -a sleep 0
    sudo pmset -a displaysleep 0
    sudo pmset -a disksleep 0
    sudo pmset -a autorestart 1 2>/dev/null
    sudo systemsetup -setrestartfreeze on >/dev/null 2>&1
    sudo softwareupdate --schedule off >/dev/null 2>&1
    # never log the user out for inactivity
    sudo defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 0
    sudo defaults write /Library/Preferences/com.apple.Bluetooth BluetoothAutoSeekKeyboard -bool false
    sudo defaults write /Library/Preferences/com.apple.Bluetooth BluetoothAutoSeekPointingDevice -bool false
    echo "Done."
fi

# ---- macOS 10.15 Catalina and newer: lower the safety checks ----
if [ "${OSMINOR:-0}" -ge 15 ]; then
    echo
    echo "This Mac runs macOS $(sw_vers -productVersion), which has two extra safety checks:"
    echo "  - Gatekeeper: blocks apps and scripts from the internet until approved"
    echo "  - Privacy: stops LoopPlayer reading videos in Desktop, Documents,"
    echo "    Downloads, iCloud Drive or on external/network drives"
    read -r -p "Turn Gatekeeper off (\"Allow apps from: Anywhere\"; admin password)? [y/N] " yn
    if [ "$yn" = y ] || [ "$yn" = Y ]; then
        sudo spctl --master-disable && echo "Gatekeeper is off."
    fi
    echo
    echo "macOS doesn't let a script switch off the privacy check; it takes 30"
    echo "seconds by hand. Only needed if your videos are in one of those places."
    read -r -p "Open the Full Disk Access settings now? [y/N] " yn
    if [ "$yn" = y ] || [ "$yn" = Y ]; then
        echo "In the window that opens: click the lock and enter the password,"
        echo "click +, press Cmd-Shift-G, type  /bin/bash  , press Return, click Open."
        echo "Then come back here."
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        read -n 1 -s -r -p "Press any key when done."
        echo
    fi
fi

# ---- a LoopPlayer shortcut in Applications (the real folder is ~/LoopPlayer) ----
for apps in /Applications "$HOME/Applications"; do
    mkdir -p "$apps" 2>/dev/null
    if [ -w "$apps" ]; then
        [ -L "$apps/LoopPlayer" ] && rm -f "$apps/LoopPlayer"
        [ -e "$apps/LoopPlayer" ] || ln -s "$DEST" "$apps/LoopPlayer"
        echo "Shortcut: $apps/LoopPlayer"
        break
    fi
done

launchctl load -w "$PLIST"

echo
echo "Installed in $DEST  (shortcut: LoopPlayer in Applications)."
echo "Playing videos from:  $("$LP" status | sed -n 's/^Folder: *//p')"
echo "It starts now and at every login."
echo "Still to do by hand: turn on automatic login for this user"
echo "(System Preferences > Users & Groups > Login Options)."
echo "Then quit Terminal, and see \"BEFORE YOU RELY ON IT\" in README.txt."
read -n 1 -s -r -p "Press any key to close."
