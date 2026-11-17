LOOPPLAYER ON LINUX  (Debian, Ubuntu, Kubuntu, Raspberry Pi OS, Mint ...)
===================
Same player as the Mac version, same loopplayer.sh. Plays every .mp4 and
.mov in a folder (and its subfolders) on an endless loop in fullscreen VLC,
with matching .srt subtitles if wanted, and carries on from roughly where it
was (10-20 seconds) after a crash, reboot or power cut.

INSTALL
  1. Log in on the machine's own screen as the user who will show the video.
  2. In a terminal, in this folder:      bash install-debian.sh
     (not with sudo; it asks for the password itself where needed)
     It installs vlc and curl if missing, asks for the video folder and
     about subtitles, turns off screen locking and blanking (KDE/Kubuntu
     and GNOME), offers automatic login (SDDM, LightDM or GDM), and starts.
  It copies itself to ~/LoopPlayer and starts again at every login.

CONTROLS  (terminal, or "LoopPlayer: ..." in the applications menu)
  ~/LoopPlayer/loopplayer.sh stop      stop, e.g. to change the videos
  ~/LoopPlayer/loopplayer.sh start     start again (a reboot also does)
  ~/LoopPlayer/loopplayer.sh restart   restart VLC at the same spot
  ~/LoopPlayer/loopplayer.sh reset     first video, loop count 0, re-sorted
  ~/LoopPlayer/loopplayer.sh status    where it is, and the playlist
  bash ~/LoopPlayer/uninstall-debian.sh    remove from login (videos kept)
Over SSH, stop/start/status work too:  the same commands.

UPDATING THE VIDEOS
Only change the folder while the player is stopped: stop, change, start.
New videos go on the END of the playlist; "reset" sorts everything again.

PLAYLIST, SUBTITLES, SETTINGS
Exactly as on the Mac; see README.txt. Settings are in
~/LoopPlayer/settings.txt:
  VIDEO_FOLDER=/home/you/Videos/loop
  SUBTITLES=yes
  FULLSCREEN=yes
  SUBTITLE_SIZE=70         optional: subtitle size in percent
  HARDWARE_DECODING=no     optional: decode on the processor only
  ASPECT=4:3               optional: show every video at this shape
  CROP=4:3                 optional: crop every video to this shape
  CROP_SIDES=180           optional: cut pixels off left and right (subtitles
                           stay centred; replaces CROP)

HOW IT RUNS
- VLC dropping out of fullscreen is put back within ~10 seconds. (Raising
  it over other windows needs the wmctrl package, if you want that.)
- A systemd user service (loopplayer.service) runs the watcher and restarts
  it if it dies; the watcher restarts VLC if VLC crashes, freezes, is
  closed, or stays paused for a minute.
- ~/.config/autostart/loopplayer.desktop starts that service at login.
- VLC runs with no player window, only the video.
- Log:  ~/LoopPlayer/state/loopplayer.log     (VLC's own: loopplayer.log.vlc)
        journalctl --user -u loopplayer       (service starts and stops)

KUBUNTU / KDE PLASMA
- Screen locking, dimming, screen-off and sleep are turned off by the
  installer. Check it took: System Settings > Screen Locking (lock
  automatically: off) and > Power Management (all three off on AC power).
- Plasma is set up as a kiosk:
    - a window rule keeps VLC fullscreen, on top of everything, without a
      border, out of the taskbar and Alt-Tab, and never minimised. You can
      see or switch it off in System Settings > Window Management > Window
      Rules ("LoopPlayer: VLC fullscreen on top").
    - one virtual desktop, so VLC can't end up on another one
    - no hot corners, so a bumped mouse doesn't open the Overview
    - each login starts with an empty desktop instead of reopening the
      apps from last time
  To get at the desktop while it plays, stop the player first (Ctrl-Alt-T
  opens a terminal: ~/LoopPlayer/loopplayer.sh stop).
- Automatic login goes into the same kind of session you installed from
  (Wayland or X11). VLC always shows the video through the X11 layer, which
  is the more reliable choice for VLC 3 fullscreen on either.
- VLC from Discover may be the snap version. The installer adds the normal
  (apt) version as well and LoopPlayer uses that one; both can stay.
- Turn off update pop-ups: System Settings > Software Update > Notification
  frequency: Never. Also consider Do Not Disturb for notifications.

BEFORE YOU RELY ON IT
The player logic was tested against VLC 3 on Linux. The installer parts
(login start, automatic login, screen-blanking settings) could not be tested
on a real desktop, so check on each machine:
 1. Reboot. Does it log in by itself and does the video fill the screen,
    with no panel, dock or window on top?
    - GNOME (plain Ubuntu) shows its "Activities" overview at login, which
      can sit over the video. KDE, Xfce, LXQt or the Raspberry Pi desktop
      don't.
 2. Pull the power, plug it back in. (Set "power on after power loss" in
    the BIOS/UEFI; a Raspberry Pi does this by itself.)
 3. Kill VLC:  pkill vlc     It should be back within ~20 seconds.
 4. Leave it an hour: does the screen stay on? The installer turns off
    blanking for KDE, GNOME and X11 in general; Xfce, LXQt and others have
    their own power manager and screensaver settings, to switch off by hand.
 5. Turn off update pop-ups (e.g. "Software Updater" on Ubuntu) and
    unattended reboots if you use unattended-upgrades.
If the video stutters only under LoopPlayer, tell whoever maintains this:
that is a setup problem, not the files.
