LOOPPLAYER
==========
Plays every .mp4 and .mov in a folder you choose (and its subfolders) on an
endless loop, in
fullscreen VLC, with matching .srt subtitles if you want them. It saves its
place every 10 seconds, so after a crash, a reboot or a power cut it carries
on from roughly where it was (within about 10-20 seconds). The watcher is
very light: about 0.1% of one CPU core.
It runs on Mac OS X 10.8 Mountain Lion and later and needs nothing but VLC.
(This file is for Macs. For Debian, Ubuntu or Raspberry Pi OS, see
README-debian.txt and install-debian.sh.)

SETTING UP A MAC (once)
1. Install VLC 3.x into /Applications. Open it once by hand and click
   through any first-run windows (privacy/network question, etc.), then quit.
2. Copy this LoopPlayer folder anywhere and double-click Install.command.
   (If macOS blocks it: right-click > Open > Open. If it says you don't
   have access privileges, the file lost its "executable" mark in transit:
   copy the original .zip over and unzip it on this Mac.) It asks:
     - which folder to play (Cancel = ~/LoopPlayer/media)
     - whether to show subtitles
     - for an admin password, to stop sleep, power back on after a power
       cut, and turn off update and Bluetooth pop-ups (say yes if you can)
   It copies itself to ~/LoopPlayer (your home folder, not Applications;
   it puts a LoopPlayer shortcut in Applications), starts playing, and
   starts again at every login. On macOS 10.15 and newer it also offers to
   turn off Gatekeeper and opens the Full Disk Access settings for you.
3. System Preferences > Users & Groups > Login Options: turn on automatic
   login for this user. Without it, after a reboot the Mac waits at the
   login screen and nothing plays.

BEFORE YOU RELY ON IT  (10 minutes per Mac, with a real video playing)
The script was tested against VLC on Linux, not on a Mac, so check these:
 1. Reboot. Does the video come up by itself, filling the whole screen,
    with no menu bar, Dock or other window showing? Is the picture smooth?
 2. Pull the power cord mid-video, plug it back in. Does the Mac switch on
    by itself and carry on near where it was, with nothing on top?
    (If the Mac's clock battery is dead, an old OS X may show a "date and
    time" warning after a power cut. Replace the battery if you see that.)
 3. In Activity Monitor, force-quit VLC. It should be back within ~20 s.
 4. Leave it overnight and look at it in the morning.
Things only you can set, per Mac:
 - Automatic login on (not possible with FileVault on, so FileVault off).
 - Laptops: lid open, power adapter in.
 - System Preferences > Security & Privacy > General: "Require password
   after sleep or screen saver" off (the installer does this on 10.12 and
   older; newer systems need it done by hand).
 - System Preferences > Mission Control > Hot Corners: all set to "-".
 - System Preferences > Energy Saver > Schedule: nothing ticked, unless
   you want set opening hours (it resumes when the Mac comes back on).
 - No other apps in System Preferences > Users & Groups > Login Items.
 - Unplug the keyboard and mouse if the public can reach them. A key press
   or an Apple Remote can pause VLC; the script un-pauses after a minute
   and restarts VLC if someone quits it, but it can't stop people trying.
 - If this Mac had VLC on it before: VLC > Preferences > Reset All, once.
 - Notifications: sign out of iCloud/Messages/Mail on this user, so
   nothing slides in over the video.
 - Don't let the disk run full; the saved place needs a little free space.

UPDATING THE VIDEOS
Only change the folder while the player is stopped:
  1. double-click "Stop Player"
  2. add, remove or rename videos (and .srt files)
  3. double-click "Start Player" (rebooting also starts it)
It resumes where it stopped. New videos go on the END of the playlist, so
nothing you've already watched is replayed. Deleted videos are dropped; if
it was in the middle of one, it carries on with the video now in that slot.

THE PLAYLIST
- Only .mp4 and .mov files are played. Everything else is ignored.
- Built from the chosen folder and all its subfolders, in natural order,
  lowest first: capitals don't matter and numbers count by value, so
  "2 intro" comes before "10 finale". A subfolder's videos play together,
  at the place where the subfolder's name sorts.
      1 opening.mp4
      2 talks/1.mp4, 2 talks/2.mp4, ... 2 talks/10.mp4
      3 closing.mov
- Videos added later go on the END (in the same order among themselves),
  so nothing already watched is replayed. "Reset Loop" starts from scratch:
  first video, loop count 0, and the whole list sorted again.
- The order is kept in ~/LoopPlayer/state/playlist.txt. You can edit it
  while the player is stopped (a Reset Loop sorts it again).

SUBTITLES
- Put "Name.srt" next to "Name.mp4", or in a folder called "sub" or "subs"
  in the same folder as the video (same name; capitals don't matter):
      Talks/Name.mp4
      Talks/subs/Name.srt
  If there's one in both places, the one next to the video is used.
  If there's no .srt, that video plays without subtitles.
- Turn subtitles off with SUBTITLES=no in settings.txt.
- If accented letters look wrong, save the .srt as UTF-8.

DAY TO DAY (double-click these in ~/LoopPlayer)
- Choose Folder    play a different folder. A different folder starts its
                   playlist from the beginning.
- Reset Loop       back to the first video at 0:00, loop count back to 0,
                   playlist sorted again.
- Status           which video, where in it, loop count, playlist, subtitles.
- Stop Player /    stop and start again around folder updates (see above).
  Start Player     A stopped player still starts by itself after a reboot.
- Restart Player   restart VLC at the same spot (e.g. after a settings change).
- Uninstall        stop for good. Videos and saved place are kept.

TIP FOR OLD MACS
Mountain Lion-era Macs can't decode HEVC (H.265) in hardware, and they
struggle with 4K or high-bitrate ProRes. For smooth, cool-running playback,
use H.264 at 1080p or below, about 8-15 Mbps.

SETTINGS  (~/LoopPlayer/settings.txt - edit, then Restart Player)
  VIDEO_FOLDER=/Users/you/Movies/Loop
  SUBTITLES=yes
  FULLSCREEN=yes
  (optional extras: see PICTURE AND SUBTITLE FIXES below)

PICTURE AND SUBTITLE FIXES  (lines in settings.txt, then Restart Player)
  SUBTITLE_SIZE=70        subtitles at 70% of normal size (10 to 500)
  HARDWARE_DECODING=no    if a Mac shows a border all round a video that
                          plays full-height elsewhere, try this first: its
                          graphics chip may be decoding the picture wrong
  ASPECT=4:3              show every video as 4:3. If VLC sees a 4:3
                          video as wider than it is, this fixes the border
                          and keeps the whole picture and centred subtitles
  CROP=4:3                crop every video to 4:3. Also removes the border,
                          but can cut off the picture's edges and VLC then
                          puts subtitles off-centre. Use if ASPECT doesn't help
  CROP_SIDES=180          the same crop, but subtitles stay centred: cuts
                          this many pixels off the left and the right of
                          every video. 180 matches CROP=4:3 for 1440x1080
                          files. Use instead of CROP (CROP is then ignored)
Remove a line to turn it off.

FOLDERS ON EXTERNAL DRIVES, AND macOS 10.15 CATALINA OR NEWER
If the folder isn't there (drive not plugged in or not mounted yet), the
player waits and starts as soon as it appears. The playlist and saved place
are kept.
On 10.15 and newer (Catalina, Big Sur, Monterey, Ventura ...), macOS
silently stops LoopPlayer reading videos kept in Desktop, Documents,
Downloads, iCloud Drive or on an external or network drive. Nothing
plays, and the log says "CAN'T READ". Either:
  - keep the videos in a folder in your home folder that isn't one of
    those, e.g. ~/LoopPlayer/media or ~/Movies, and choose that folder; or
  - give bash access: System Preferences > Security & Privacy > Privacy >
    Full Disk Access, unlock, click +, press Cmd-Shift-G, type /bin/bash,
    Open. Then double-click Restart Player. (This lets every script on the
    Mac read everything, which is fine on a Mac used only as a player.)
10.8-10.14 don't have this restriction.

WHAT IT HANDLES BY ITSELF
- VLC crashes, or someone quits it: VLC is reopened at the saved place.
- VLC freezes (picture stuck or not answering for ~50 s): restarted.
- VLC gets paused: playing again after a minute.
- VLC drops out of fullscreen: put back within ~10 seconds.
- Another app, window or desktop (Space) covers VLC: VLC is brought back
  to the front after 1-2 minutes. (KEEP_IN_FRONT=no turns this off.)
- A video that won't open (damaged, wrong format): skipped, no error window.
- A second VLC appears (macOS reopening it after a power cut): closed.
- Someone presses Stop in VLC: playback continues after a few seconds.
- The script itself dies: macOS (launchd) starts it again.
- Reboot / power cut: starts at login and resumes. The saved place
  alternates between two files and each save is pushed to the disk, so a
  power cut in the middle of a save still leaves the one before it.

FILES
  ~/LoopPlayer/settings.txt         settings
  ~/LoopPlayer/state/state.0, .1    saved place: file, position, loop count
  ~/LoopPlayer/state/playlist.txt   play order
  ~/LoopPlayer/state/loopplayer.log what happened and when

VLC is controlled through its built-in web interface, only on 127.0.0.1
port 48765. If the firewall asks about VLC accepting connections, click Allow.
