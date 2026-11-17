#!/bin/bash
# LoopPlayer installer for Debian, Ubuntu, Kubuntu (KDE), Raspberry Pi OS and
# relatives.
# Run it as the user who will be logged in on the screen (not with sudo):
#     bash install-debian.sh
# Safe to run again.

if [ "$(id -u)" = 0 ]; then
    echo "Run this as the normal user who logs in on the screen, not as root or with sudo."
    echo "(It will ask for the sudo password itself where needed.)"
    exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/LoopPlayer"
UNIT_DIR="$HOME/.config/systemd/user"
AUTOSTART="$HOME/.config/autostart/loopplayer.desktop"
APPS="$HOME/.local/share/applications"
LP="$DEST/loopplayer.sh"

echo "== LoopPlayer install (Debian) =="

# ---- packages ----
need=""
# the apt VLC, even if a snap VLC is installed: the snap one is slower to
# start and can't see external drives without extra steps
[ -x /usr/bin/vlc ] || need="$need vlc"
command -v curl >/dev/null || need="$need curl"
if [ -n "$need" ]; then
    echo "Missing packages:$need"
    [ -x /snap/bin/vlc ] && echo "(VLC is installed as a snap; the apt version is recommended for LoopPlayer. Both can stay installed.)"
    read -r -p "Install them now with apt (needs the sudo password)? [Y/n] " yn
    case "$yn" in n|N) echo "Install them, then run this again."; exit 1 ;; esac
    # shellcheck disable=SC2086
    sudo apt-get update && sudo apt-get install -y $need || { echo "apt failed."; exit 1; }
fi
if ! command -v systemctl >/dev/null || ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "!! This needs systemd with a user session (standard on Debian, Ubuntu and Kubuntu with a desktop)."
    echo "   Run this from a terminal inside the desktop session of the screen user."
    exit 1
fi
echo "Found $(/usr/bin/vlc --version 2>/dev/null | head -1)"

# ---- files ----
systemctl --user stop loopplayer.service 2>/dev/null
mkdir -p "$DEST/media" "$DEST/state" "$UNIT_DIR" "$(dirname "$AUTOSTART")" "$APPS"
if [ "$SRC" != "$DEST" ]; then
    cp -f "$SRC/loopplayer.sh" "$SRC/install-debian.sh" "$SRC/uninstall-debian.sh" "$SRC/README-debian.txt" "$DEST/"
fi
chmod +x "$DEST/"*.sh

# ---- settings (asked only the first time; edit settings.txt later) ----
if [ ! -f "$DEST/settings.txt" ]; then
    echo
    echo "Which folder should the playlist come from? (.mp4 and .mov, subfolders included)"
    read -r -e -p "Folder [$DEST/media]: " DIR
    DIR="${DIR/#\~/$HOME}"; DIR="${DIR%/}"; [ -z "$DIR" ] && DIR="$DEST/media"
    [ -d "$DIR" ] || echo "   (that folder doesn't exist yet - the player will wait for it)"
    "$LP" set VIDEO_FOLDER "$DIR" >/dev/null
    read -r -p "Show subtitles when a matching .srt file is next to a video? [Y/n] " yn
    case "$yn" in n|N) "$LP" set SUBTITLES no >/dev/null ;; *) "$LP" set SUBTITLES yes >/dev/null ;; esac
    "$LP" set FULLSCREEN yes >/dev/null
fi

# ---- keep it running: a systemd user service, restarted if it ever dies ----
cat >"$UNIT_DIR/loopplayer.service" <<EOF
[Unit]
Description=LoopPlayer video loop

[Service]
ExecStart=/bin/bash "$LP" run
Restart=always
RestartSec=10
EOF

# ---- start it at login: the desktop runs this once the screen is up, and
#      it hands the screen's details (DISPLAY etc.) to the service ----
cat >"$DEST/session-start.sh" <<'EOF'
#!/bin/bash
# Run by the desktop at login (see ~/.config/autostart/loopplayer.desktop).
for v in DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP; do
    [ -n "${!v}" ] && systemctl --user import-environment "$v"
done
systemctl --user restart loopplayer.service
EOF
chmod +x "$DEST/session-start.sh"
cat >"$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=LoopPlayer
Comment=Start the video loop at login
Exec=/bin/bash "$DEST/session-start.sh"
X-GNOME-Autostart-enabled=true
EOF

# ---- menu entries (the Debian stand-ins for the Mac's double-click files) ----
entry() {   # entry "Name" terminal(true|false) arguments...
    local name="$1" term="$2"; shift 2
    cat >"$APPS/loopplayer-$(echo "$name" | tr 'A-Z ' 'a-z-').desktop" <<EOF
[Desktop Entry]
Type=Application
Name=LoopPlayer: $name
Exec=/bin/bash "$LP" $*
Terminal=$term
Categories=AudioVideo;
EOF
}
entry "Stop"       false stop
entry "Start"      false start
entry "Restart"    false restart
entry "Reset Loop" false reset
entry "Status"     true  status wait

# ---- things that would blank or lock the screen ----
# GNOME and relatives (harmless elsewhere)
if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null
    gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null
    gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing 2>/dev/null
    gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null
    gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null
fi
# KDE Plasma (Kubuntu): screen locker and power management
KW=""
command -v kwriteconfig6 >/dev/null && KW=kwriteconfig6
[ -z "$KW" ] && command -v kwriteconfig5 >/dev/null && KW=kwriteconfig5
if [ -n "$KW" ]; then
    echo "KDE Plasma found: turning off screen locking, dimming, screen-off and sleep,"
    echo "and setting up Plasma as a kiosk (VLC always fullscreen and on top, one"
    echo "desktop, no hot corners, no reopening of last session's apps)."
    $KW --file kscreenlockerrc --group Daemon --key Autolock false
    $KW --file kscreenlockerrc --group Daemon --key LockOnResume false
    for prof in AC Battery LowBattery; do
        # Plasma 6
        $KW --file powerdevilrc --group $prof --group Display --key DimDisplayWhenIdle false
        $KW --file powerdevilrc --group $prof --group Display --key TurnOffDisplayWhenIdle false
        $KW --file powerdevilrc --group $prof --group SuspendAndShutdown --key AutoSuspendAction 0
        # Plasma 5 (a setting is off when its entry is absent)
        for grp in DimDisplay DPMSControl SuspendSession; do
            $KW --file powermanagementprofilesrc --group $prof --group $grp --key idleTime --delete
            $KW --file powermanagementprofilesrc --group $prof --group $grp --key suspendType --delete
        done
    done
    # ---- Plasma as a kiosk ----
    KR=kreadconfig6; command -v $KR >/dev/null || KR=kreadconfig5
    # a KWin window rule for VLC's window (works on Wayland and X11):
    # always fullscreen, above everything, no border, never minimised, not
    # in the taskbar or Alt-Tab, and allowed to take focus when it restarts
    R=loopplayer-vlc
    $KW --file kwinrulesrc --group $R --key Description "LoopPlayer: VLC fullscreen on top"
    $KW --file kwinrulesrc --group $R --key wmclass vlc
    $KW --file kwinrulesrc --group $R --key wmclassmatch 1          # exact
    $KW --file kwinrulesrc --group $R --key wmclasscomplete false
    for k in fullscreen above noborder skiptaskbar skipswitcher skippager; do
        $KW --file kwinrulesrc --group $R --key $k true
        $KW --file kwinrulesrc --group $R --key ${k}rule 2         # 2 = force
    done
    $KW --file kwinrulesrc --group $R --key minimize false
    $KW --file kwinrulesrc --group $R --key minimizerule 2
    $KW --file kwinrulesrc --group $R --key fsplevel 0             # no focus-stealing block
    $KW --file kwinrulesrc --group $R --key fsplevelrule 2
    # add it to the list of rules without touching any existing ones
    rules=$($KR --file kwinrulesrc --group General --key rules 2>/dev/null)
    case ",$rules," in *",$R,"*) ;; *) rules="${rules:+$rules,}$R" ;; esac
    $KW --file kwinrulesrc --group General --key rules "$rules"
    $KW --file kwinrulesrc --group General --key count "$(printf '%s' "$rules" | tr ',' '\n' | grep -c .)"
    # one virtual desktop, so VLC can't end up on another one
    $KW --file kwinrc --group Desktops --key Number 1
    $KW --file kwinrc --group Desktops --key Rows 1
    # no hot corners (a bumped mouse would open the Overview over the video)
    for e in Effect-overview Effect-windowview Effect-desktopgrid Effect-PresentWindows; do
        $KW --file kwinrc --group $e --key BorderActivate 9            # 9 = none
        $KW --file kwinrc --group $e --key BorderActivateAll 9
    done
    $KW --file kwinrc --group ElectricBorders --key TopLeft None
    # start each login with an empty desktop: don't reopen last session's apps
    $KW --file ksmserverrc --group General --key loginMode emptySession
    # apply the window manager changes now
    for q in qdbus6 qdbus qdbus-qt5; do
        command -v $q >/dev/null && { $q org.kde.KWin /KWin reconfigure >/dev/null 2>&1; break; }
    done

    # tell the running power manager (otherwise it applies at next login)
    for q in qdbus6 qdbus qdbus-qt5; do
        command -v $q >/dev/null && { $q org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement reparseConfiguration >/dev/null 2>&1; break; }
    done
fi

# ---- automatic login ----
echo
ME="$(id -un)"
# which login manager is actually in use
DM=""
[ -e /etc/systemd/system/display-manager.service ] &&
    DM=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)
if [ -z "$DM" ] || [ "$DM" = display-manager ]; then
    if [ -x /usr/bin/sddm ]; then DM=sddm
    elif [ -d /etc/lightdm ]; then DM=lightdm
    elif [ -f /etc/gdm3/daemon.conf ] || [ -f /etc/gdm3/custom.conf ]; then DM=gdm3
    fi
fi
case "$DM" in
sddm)
    # log in to the same kind of session as the one we're in now
    SESS=""
    if [ "$XDG_SESSION_TYPE" = wayland ]; then
        for f in /usr/share/wayland-sessions/plasma.desktop /usr/share/wayland-sessions/plasmawayland.desktop; do
            [ -f "$f" ] && { SESS=$(basename "$f"); break; }
        done
    fi
    if [ -z "$SESS" ]; then
        for f in /usr/share/xsessions/plasmax11.desktop /usr/share/xsessions/plasma.desktop /usr/share/wayland-sessions/plasma.desktop; do
            [ -f "$f" ] && { SESS=$(basename "$f"); break; }
        done
    fi
    read -r -p "Log in '$ME' automatically at boot (SDDM${SESS:+, session $SESS}; needs the sudo password)? [y/N] " yn
    if [ "$yn" = y ] || [ "$yn" = Y ]; then
        sudo mkdir -p /etc/sddm.conf.d &&
        printf '[Autologin]\nUser=%s\nSession=%s\nRelogin=false\n' "$ME" "$SESS" |
            sudo tee /etc/sddm.conf.d/50-loopplayer-autologin.conf >/dev/null && echo "Done."
    fi ;;
lightdm)
    read -r -p "Log in '$ME' automatically at boot (LightDM; needs the sudo password)? [y/N] " yn
    if [ "$yn" = y ] || [ "$yn" = Y ]; then
        sudo mkdir -p /etc/lightdm/lightdm.conf.d &&
        printf '[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n' "$ME" |
            sudo tee /etc/lightdm/lightdm.conf.d/50-loopplayer-autologin.conf >/dev/null && echo "Done."
    fi ;;
gdm|gdm3)
    CONF=/etc/gdm3/custom.conf; [ -f "$CONF" ] || CONF=/etc/gdm3/daemon.conf
    read -r -p "Log in '$ME' automatically at boot (GDM; needs the sudo password)? [y/N] " yn
    if [ "$yn" = y ] || [ "$yn" = Y ]; then
        sudo cp -n "$CONF" "$CONF.before-loopplayer" &&
        sudo sed -i -e '/^[[:space:]]*AutomaticLogin\(Enable\)\{0,1\}[[:space:]]*=/d' \
                    -e "s/^\[daemon\].*/[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$ME/" "$CONF" &&
        echo "Done. (The original is saved as $CONF.before-loopplayer)"
    fi ;;
*)
    echo "Automatic login: set it up in your login manager's settings for user '$ME'." ;;
esac

# ---- go ----
systemctl --user daemon-reload
/bin/bash "$DEST/session-start.sh"

echo
echo "Installed. Playing videos from:  $("$LP" status | sed -n 's/^Folder: *//p')"
echo "It starts now and at every login. Controls:"
echo "    $LP stop | start | restart | reset | status"
echo "(also in the applications menu as \"LoopPlayer: ...\")"
echo "See README-debian.txt, especially \"BEFORE YOU RELY ON IT\"."
