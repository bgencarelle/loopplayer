#!/bin/bash
# =============================================================================
#  LoopPlayer - crash/reboot-proof looping video player
#  for macOS (10.8+) and Debian-family Linux.
#
#  macOS:  needs only VLC 3.x in /Applications. Everything else ships with
#          the system (bash 3.2, curl, awk, sed, launchd). Install.command.
#  Debian: needs the vlc and curl packages. install-debian.sh.
#
#  Usage:  loopplayer.sh run       (started at login by launchd / systemd)
#          loopplayer.sh stop      stop playing (until "start" or next login)
#          loopplayer.sh start     start playing again
#          loopplayer.sh reset     start from the first file, loop count 0
#          loopplayer.sh restart   restart VLC, resuming where it was
#          loopplayer.sh status    show where playback is
#          loopplayer.sh set KEY VALUE   change a setting in settings.txt
#
#  The video folder is read each time the player starts: videos already in
#  the playlist keep their order, new ones go on the end, and deleted ones
#  are dropped. Change the folder only while the player is stopped.
#
#  User settings live in ~/LoopPlayer/settings.txt (see README.txt):
#    VIDEO_FOLDER=/path/to/folder   the playlist is built from this folder
#                                   (.mp4 and .mov only, subfolders included)
#    SUBTITLES=yes|no               use "name.srt" next to "name.mp4"
#    FULLSCREEN=yes|no
#    KEEP_IN_FRONT=yes|no           bring VLC back if another app or
#                                   desktop covers it for 1-2 minutes
#    ASPECT=4:3                     optional: tell VLC every video's shape
#    CROP=4:3                       optional: crop every video to this shape
#    CROP_SIDES=180                 optional: cut this many pixels off the
#                                   left and right of every video (keeps
#                                   subtitles centred; replaces CROP)
#    SUBTITLE_SIZE=70               optional: subtitle size in percent (10-500)
#    HARDWARE_DECODING=no           optional: decode on the processor only
# =============================================================================

export LC_ALL=C   # byte-wise names, '.' decimals, predictable sort
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH:/snap/bin

# ----------------------------- fixed settings --------------------------------
BASE="${LOOPPLAYER_HOME:-$HOME/LoopPlayer}"
SETTINGS="$BASE/settings.txt"
STATE_DIR="$BASE/state"
PORT="${LOOPPLAYER_PORT:-48765}"           # local-only control port for VLC
PASSWORD="loopplayer"                      # VLC requires one; bound to 127.0.0.1
POLL=10           # seconds between checks/saves (resume lands within this).
                  # Each check costs one small request, one awk, one sync.
STALL_LIMIT=4     # checks with no progress / no answer before VLC is
                  # restarted (about 40-50 seconds)
PAUSE_LIMIT=6     # checks VLC may stay paused before it is un-paused (1 min)
START_WAIT=120    # seconds to wait for VLC to come up (old Macs, cold disks)
MAC_LEVEL=2       # Mac-only VLC options in use; lowered automatically if
                  # this VLC version refuses to start with them

# ----------------------------- user settings ---------------------------------
setting() {   # setting KEY DEFAULT
    local v=""
    [ -f "$SETTINGS" ] && v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$SETTINGS" | tail -1 | sed 's/[[:space:]]*$//')
    [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}
yes_no() { case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in y|yes|1|on|true) echo 1 ;; *) echo 0 ;; esac; }

load_settings() {
    MEDIA_DIR=$(setting VIDEO_FOLDER "$BASE/media")
    MEDIA_DIR="${MEDIA_DIR%/}"; MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"
    SUBTITLES=$(yes_no "$(setting SUBTITLES yes)")
    FULLSCREEN=$(yes_no "$(setting FULLSCREEN yes)")
    KEEP_FRONT=$(yes_no "$(setting KEEP_IN_FRONT yes)")
    CROP=$(setting CROP "")
    SUB_SIZE=$(setting SUBTITLE_SIZE ""); SUB_SIZE="${SUB_SIZE%\%}"
    case "$SUB_SIZE" in ''|*[!0-9]*) SUB_SIZE="" ;; *) { [ "$SUB_SIZE" -lt 10 ] || [ "$SUB_SIZE" -gt 500 ]; } && SUB_SIZE="" ;; esac
    HWDEC=$(setting HARDWARE_DECODING yes | tr 'A-Z' 'a-z')
    ASPECT=$(setting ASPECT "")
    CROP_SIDES=$(setting CROP_SIDES "")
    case "$CROP_SIDES" in ''|*[!0-9]*) CROP_SIDES="" ;; *) { [ "$CROP_SIDES" -lt 1 ] || [ "$CROP_SIDES" -gt 3000 ]; } && CROP_SIDES="" ;; esac
    # only a plain W:H is passed on; anything else could stop VLC starting
    case "$CROP" in *[!0-9:]*|:*|*:|*:*:*) CROP="" ;; *:*) ;; *) CROP="" ;; esac
    case "$ASPECT" in *[!0-9:]*|:*|*:|*:*:*) ASPECT="" ;; *:*) ;; *) ASPECT="" ;; esac
}

set_setting() {   # rewrite settings.txt with KEY=VALUE (other lines kept)
    [ -f "$SETTINGS" ] || cat >"$SETTINGS" <<'EOF'
# LoopPlayer settings. After editing, double-click "Restart Player".
#   VIDEO_FOLDER  folder the playlist is built from (changing it starts fresh)
#   SUBTITLES     yes = show "name.srt" for "name.mp4" when it exists
#   FULLSCREEN    yes / no (yes also puts VLC back into fullscreen if it
#                 drops out of it)
#   KEEP_IN_FRONT yes / no: bring VLC back to the front if another app or
#                 desktop covers it for 1-2 minutes
#   ASPECT        e.g. 4:3 = show every video at that shape (try before CROP:
#                 keeps the whole picture and centred subtitles)
#   CROP_SIDES    e.g. 180 = cut 180 pixels off the left and the right of
#                 every video. Subtitles stay centred. Used instead of CROP.
#   CROP          e.g. 4:3 = crop every video to that shape. Leave out for
#                 no cropping. (Can push subtitles off-centre.)
#   SUBTITLE_SIZE subtitle size in percent: 100 = normal, 70 = smaller
#   HARDWARE_DECODING   no = decode on the processor only (for Macs whose
#                 graphics chip shows the picture wrong)
EOF
    K="$1" V="$2" awk 'BEGIN{k=ENVIRON["K"]; v=ENVIRON["V"]; done=0}
        { line=$0; s=line; sub(/^[ \t]*/, "", s)
          if (index(s, k "=") == 1 || index(s, k " =") == 1) { if (!done) print k "=" v; done=1 } else print line }
        END{ if (!done) print k "=" v }' "$SETTINGS" >"$SETTINGS.tmp" && mv -f "$SETTINGS.tmp" "$SETTINGS"
}

load_settings
# -----------------------------------------------------------------------------

STATE="$STATE_DIR/state.txt"
FOLDER_FILE="$STATE_DIR/folder.txt"
PLAYLIST="$STATE_DIR/playlist.txt"
RESET_FLAG="$STATE_DIR/RESET"
RESTART_FLAG="$STATE_DIR/RESTART"
LOG="$STATE_DIR/loopplayer.log"
PIDFILE="$STATE_DIR/vlc.pid"
URL="http://127.0.0.1:$PORT/requests"

mkdir -p "$STATE_DIR"
# only create the default folder; never create a folder on a drive that
# simply isn't mounted yet
[ "$MEDIA_DIR" = "$BASE/media" ] && mkdir -p "$MEDIA_DIR"

log() {
    if [ -f "$LOG" ] && [ "$(wc -c <"$LOG")" -gt 1000000 ]; then mv -f "$LOG" "$LOG.old"; fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

# ------------------------------ VLC location ---------------------------------
find_vlc() {
    if [ -n "$VLC_BIN" ]; then echo "$VLC_BIN"; return; fi
    # (on Linux the apt version first; the snap version as a fallback)
    for v in "/Applications/VLC.app/Contents/MacOS/VLC" "$HOME/Applications/VLC.app/Contents/MacOS/VLC" /usr/bin/vlc /snap/bin/vlc; do
        [ -x "$v" ] && { echo "$v"; return; }
    done
    command -v vlc 2>/dev/null
}

# ------------------------------ helpers --------------------------------------
urlenc() {   # percent-encode a path (spaces as %20, which VLC needs)
    local s="$1" o="" c i
    for (( i=0; i<${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9/._~-]) o="$o$c" ;;
            *) o="$o$(printf '%%%02X' "'$c")" ;;
        esac
    done
    printf '%s' "$o"
}

vlc_get() {  # vlc_get <page> [query]  -> prints body, fails if VLC not answering
    curl -s -f -m 3 -u ":$PASSWORD" "$URL/$1${2:+?$2}"
}

xml_val() {  # xml_val <tag> <xml>
    printf '%s\n' "$2" | sed -n "s:.*<$1>\(.*\)</$1>.*:\1:p" | head -1 | tr ',' '.'
}

fcmp() {     # fcmp "<awk expression using a and b>" a b  -> exit status
    awk -v a="$2" -v b="$3" "BEGIN{exit !($1)}"
}

is_video() {   # only .mp4 and .mov (any case); nothing hidden
    local n
    n=$(printf '%s' "${1##*/}" | tr 'A-Z' 'a-z')
    case "$n" in .*) return 1 ;; *.mp4|*.mov) return 0 ;; esac
    return 1
}

# Every .mp4/.mov under the video folder, subfolders included, one path per
# line (relative to the folder), in natural order: upper/lower case ignored,
# numbers by value (2 before 10), a folder's contents kept together at the
# folder's place in the list. Hidden files and folders are left out.
list_videos() {
    find -L "$MEDIA_DIR/" -type f 2>/dev/null | P="$MEDIA_DIR/" awk '
        BEGIN { plen = length(ENVIRON["P"]) }
        {
            rel = substr($0, plen + 1); sub(/^\/+/, "", rel)
            if (rel == "" || rel ~ /^\./ || rel ~ /\/\./) next
            low = tolower(rel)
            if (low !~ /\.(mp4|mov)$/) next
            sub(/\.[^.\/]*$/, "", low)            # order by name, not extension
            key = ""
            while (match(low, /[0-9]+/)) {         # pad numbers so 2 < 10
                num = substr(low, RSTART, RLENGTH); sub(/^0+/, "", num)
                key = key substr(low, 1, RSTART - 1) substr("00000000000000000000" num, length(num) + 1)
                low = substr(low, RSTART + RLENGTH)
            }
            key = key low
            gsub(/\//, "\001", key)                # "a/x" before "a b/x"
            print key "\t" rel
        }' | sort | cut -f2-
}

file_size() { ls -ln "$1" 2>/dev/null | awk '{print $5}'; }

sub_for() {   # sub_for "dir/Video.mp4" -> full path of its .srt, if any
    [ "$SUBTITLES" = 1 ] || return 1    # (same name; upper/lower case ignored)
    local rel="${1%.*}" dir f want found=1
    dir="$MEDIA_DIR/$rel"; dir="${dir%/*}"; want="${rel##*/}.srt"
    shopt -s nocasematch
    for f in "$dir"/*.[sS][rR][tT]; do
        [ -f "$f" ] || continue
        if [[ "${f##*/}" == "$want" ]]; then printf '%s' "$f"; found=0; break; fi
    done
    shopt -u nocasematch
    return $found
}

# ------------------------------ playlist -------------------------------------
# playlist.txt holds one video per line (path inside the video folder), in
# play order. First time: natural order (see list_videos). Later: new videos
# go on the end, vanished ones are dropped. "Reset Loop" re-sorts everything.
FILES=()
load_playlist() {
    FILES=()
    local line
    if [ -f "$PLAYLIST" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -n "$line" ] && [ -f "$MEDIA_DIR/$line" ] && is_video "$line" && FILES+=("$line")
        done <"$PLAYLIST"
    fi
    # append anything in the folder that isn't listed yet (natural order)
    local name found
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        found=0
        for line in "${FILES[@]}"; do [ "$line" = "$name" ] && { found=1; break; }; done
        [ $found = 0 ] && { FILES+=("$name"); [ -f "$PLAYLIST" ] && log "new video, added to the end: $name"; }
    done < <(list_videos)
    write_playlist
}

write_playlist() {
    local f
    # folder looks empty (drive still mounting?): keep the saved order
    [ ${#FILES[@]} = 0 ] && return
    : >"$PLAYLIST.tmp"
    for f in "${FILES[@]}"; do printf '%s\n' "$f" >>"$PLAYLIST.tmp"; done
    mv -f "$PLAYLIST.tmp" "$PLAYLIST"
}

# VLC playlist ids, in order (only the "Playlist" node, not Media Library)
IDS=()
refresh_ids() {
    local xml id
    xml=$(vlc_get playlist.xml) || return 1
    IDS=()
    while IFS= read -r id; do [ -n "$id" ] && IDS+=("$id"); done < <(
        printf '%s\n' "$xml" | awk '/<node/{n++} n==2 && /<leaf/{ if (match($0, / id="[0-9]+"/)) print substr($0, RSTART+5, RLENGTH-6) }')
}

index_of_id() {   # sets FOUND_IDX (no subshell)
    local i
    for (( i=0; i<${#IDS[@]}; i++ )); do [ "${IDS[$i]}" = "$1" ] && { FOUND_IDX=$i; return 0; }; done
    return 1
}

# ------------------------------ saved state ----------------------------------
# The saved place alternates between two files (state.0 / state.1), each
# with a sequence number. Writing one never touches the other, so a power cut
# mid-save always leaves the previous good copy.
SEQ=0; STATE_FILE=""; SYNC_PID=""
S_IDX=0; S_NAME=""; S_POS=0; S_LOOPS=0; S_TIME=0; S_LEN=0
save_state() {   # idx name pos loops time length
    SEQ=$((SEQ+1))
    printf 'seq=%s\nindex=%s\nfile=%s\nposition=%s\nloops=%s\ntime=%s\nlength=%s\nok=1\n' \
        "$SEQ" "$1" "$2" "$3" "$4" "$5" "$6" >"$STATE_DIR/state.$((SEQ % 2))"
    # Push it to the disk now, or a power cut could lose the last ~30 s of
    # saves. In the background, and never two at once, so a slow or hung
    # drive can't stall the watcher.
    if [ -z "$SYNC_PID" ] || ! kill -0 "$SYNC_PID" 2>/dev/null; then
        sync & SYNC_PID=$!
    fi
}

R_SEQ=0; R_IDX=0; R_NAME=""; R_POS=0; R_LOOPS=0; R_TIME=0; R_LEN=0
parse_state_file() {   # -> R_* ; fails if missing or incomplete
    local k v ok=0
    R_SEQ=0; R_IDX=""; R_NAME=""; R_POS=0; R_LOOPS=0; R_TIME=0; R_LEN=0
    [ -f "$1" ] || return 1
    while IFS='=' read -r k v; do
        case "$k" in
            seq) R_SEQ=$v ;; index) R_IDX=$v ;; file) R_NAME=$v ;; position) R_POS=$v ;;
            loops) R_LOOPS=$v ;; time) R_TIME=$v ;; length) R_LEN=$v ;; ok) ok=1 ;;
        esac
    done <"$1"
    [ $ok = 1 ] || return 1
    case "$R_IDX" in ''|*[!0-9]*) return 1 ;; esac
    case "$R_SEQ" in ''|*[!0-9]*) R_SEQ=0 ;; esac
    case "$R_LOOPS" in ''|*[!0-9]*) R_LOOPS=0 ;; esac
    case "$R_POS" in 0|0.*|[0-9]e-*|[0-9].*e-*) ;; *) R_POS=0 ;; esac
    return 0
}

read_best_state() {   # newest valid copy -> S_* ; fails if none
    local f found=1 best=-1
    # state.txt / state.prev: saves from the previous version of this script
    for f in "$STATE_DIR/state.0" "$STATE_DIR/state.1" "$STATE" "$STATE.prev"; do
        parse_state_file "$f" || continue
        if [ "$R_SEQ" -gt "$best" ]; then
            best=$R_SEQ; found=0; STATE_FILE=$f
            S_IDX=$R_IDX; S_NAME=$R_NAME; S_POS=$R_POS; S_LOOPS=$R_LOOPS; S_TIME=$R_TIME; S_LEN=$R_LEN
        fi
    done
    [ $found = 0 ] && SEQ=$best
    return $found
}

clear_state() { rm -f "$STATE_DIR/state.0" "$STATE_DIR/state.1" "$STATE" "$STATE.prev"; SEQ=0; }

load_state() {
    S_IDX=0; S_NAME=""; S_POS=0; S_LOOPS=0
    read_best_state || { S_IDX=0; S_NAME=""; S_POS=0; S_LOOPS=0; }
    # prefer finding the file by name (survives reordering / removed files)
    local i
    if [ -n "$S_NAME" ]; then
        for (( i=0; i<${#FILES[@]}; i++ )); do
            [ "${FILES[$i]}" = "$S_NAME" ] && { S_IDX=$i; return; }
        done
        S_POS=0   # that file is gone: start the file now at its slot from 0
    fi
    [ "$S_IDX" -ge "${#FILES[@]}" ] && { S_IDX=0; S_POS=0; }
}

# ------------------------------ VLC control ----------------------------------
VLC_PID=""
stop_vlc() {
    [ -f "$PIDFILE" ] && VLC_PID=$(cat "$PIDFILE")
    if [ -n "$VLC_PID" ] && kill -0 "$VLC_PID" 2>/dev/null; then
        kill "$VLC_PID" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$VLC_PID" 2>/dev/null || break; sleep 0.5; done
        kill -9 "$VLC_PID" 2>/dev/null
    fi
    # anything else still holding our port (e.g. left over from a crash)
    if pkill -f "http-port=$PORT" 2>/dev/null; then sleep 2; pkill -9 -f "http-port=$PORT" 2>/dev/null; fi
    # this Mac is a player: any other VLC (e.g. one macOS reopened by itself
    # after a power cut) would sit in front of the video
    if [ "$(uname)" = Darwin ] && pkill -x VLC 2>/dev/null; then sleep 2; pkill -9 -x VLC 2>/dev/null; fi
    VLC_PID=""; rm -f "$PIDFILE"
}

start_vlc() {
    local vlc paths=() f opts
    vlc=$(find_vlc)
    [ -z "$vlc" ] && { log "ERROR: VLC not found"; return 1; }
    local srt nsubs=0
    for f in "${FILES[@]}"; do
        paths+=("$MEDIA_DIR/$f")
        # an option right after a file applies to that file only
        if srt=$(sub_for "$f"); then paths+=(":sub-file=$srt"); nsubs=$((nsubs+1)); fi
    done
    opts=(--extraintf=http --http-host=127.0.0.1 --http-port=$PORT --http-password=$PASSWORD
          --loop --no-repeat --no-random --no-play-and-exit --no-playlist-autostart
          --no-video-title-show
          --no-interact                # no error pop-ups over the video
          --no-sub-autodetect-file)    # subtitles only as we assign them
    [ "$FULLSCREEN" = 1 ] && opts+=(--fullscreen)
    [ -n "$ASPECT" ] && opts+=(--aspect-ratio="$ASPECT")
    if [ -n "$CROP_SIDES" ]; then
        # crops the decoded picture itself, so subtitles are placed on what's left
        opts+=("--video-filter=croppadd{cropleft=$CROP_SIDES,cropright=$CROP_SIDES}")
    elif [ -n "$CROP" ]; then
        opts+=(--crop="$CROP")
    fi
    [ -n "$SUB_SIZE" ] && opts+=(--sub-text-scale="$SUB_SIZE")
    case "$HWDEC" in n|no|0|off|false) opts+=(--avcodec-hw=none --codec=avcodec,all) ;; esac
    if [ "$(uname)" = Darwin ]; then
        [ "$MAC_LEVEL" -ge 1 ] && opts+=(--macosx-continue-playback=2)  # VLC's own resume off; we do it
        [ "$MAC_LEVEL" -ge 2 ] && opts+=(--no-macosx-appleremote)       # ignore stray Apple Remotes
    fi
    if [ "$(uname)" = Linux ]; then
        opts+=(--intf=dummy)    # just the video: no player window, no dialogs
    fi
    # shellcheck disable=SC2206
    [ -n "$VLC_EXTRA_OPTS" ] && opts+=($VLC_EXTRA_OPTS)
    # VLC's own messages: start a fresh file if the old one got big
    [ -n "$(find "$LOG.vlc" -size +5000k 2>/dev/null)" ] && mv -f "$LOG.vlc" "$LOG.vlc.old"
    log "starting VLC with ${#FILES[@]} file(s) from $MEDIA_DIR, $nsubs with subtitles"
    # (VLC gets the system's normal locale, not our LC_ALL=C)
    ( unset LC_ALL; [ -n "$LANG" ] || [ "$(uname)" != Linux ] || export LANG=C.UTF-8
      # Wayland desktops (e.g. Kubuntu 24.10+): VLC 3 is far more reliable in
      # fullscreen through the desktop's X11 layer (XWayland) than natively
      [ "$(uname)" = Linux ] && [ -n "$DISPLAY" ] && unset WAYLAND_DISPLAY
      exec "$vlc" "${opts[@]}" "${paths[@]}" ) >>"$LOG.vlc" 2>&1 &
    VLC_PID=$!
    echo "$VLC_PID" >"$PIDFILE"
    local n=0
    until vlc_get status.xml >/dev/null; do
        n=$((n+1)); [ $n -gt $START_WAIT ] && { log "ERROR: VLC did not answer after ${START_WAIT}s"; return 1; }
        if ! kill -0 "$VLC_PID" 2>/dev/null; then
            if [ "$(uname)" = Darwin ] && [ "$MAC_LEVEL" -gt 0 ]; then
                MAC_LEVEL=$((MAC_LEVEL-1))
                log "VLC exited at startup - trying again with fewer Mac-only options (level $MAC_LEVEL)"
            else
                log "ERROR: VLC exited at startup (is it VLC 3.x? see loopplayer.log.vlc)"
            fi
            return 1
        fi
        sleep 1
    done
    refresh_ids
    [ ${#IDS[@]} = ${#FILES[@]} ] || log "warning: VLC lists ${#IDS[@]} item(s), expected ${#FILES[@]}"
    return 0
}

# Jump to item idx at fraction pos (0..1) and confirm it took.
# Returns 1 if it could not, so the caller never saves a wrong place.
goto_pos() {
    local idx="$1" pos="$2" id st n=0 other=0 cur state p len
    id="${IDS[$idx]}"
    [ -z "$id" ] && return 1
    vlc_get status.xml "command=pl_play&id=$id" >/dev/null
    while :; do   # wait (up to ~2 minutes: sleepy disks) until it is playing
        sleep 0.5; n=$((n+1)); [ $n -gt 240 ] && return 1
        kill -0 "$VLC_PID" 2>/dev/null || return 1
        st=$(vlc_get status.xml) || continue
        cur=$(xml_val currentplid "$st"); state=$(xml_val state "$st"); len=$(xml_val length "$st")
        if [ "$state" = playing ] && [ -n "$len" ] && [ "$len" != 0 ]; then
            [ "$cur" = "$id" ] && break
            # VLC is playing something else: it could not open our file
            other=$((other+1)); [ $other -ge 8 ] && return 1
        fi
    done
    fcmp 'a>0.0005' "$pos" 0 || return 0
    local v k lo hi
    # accept landing from 1.5 s before the target to 20 s after it (the
    # checks below can take a while on a slow Mac)
    lo=$(awk -v p="$pos" -v l="$len" 'BEGIN{print p-1.5/l}')
    hi=$(awk -v p="$pos" -v l="$len" 'BEGIN{print p+20/l}')
    # exact percentage first ('.' then ',' as VLC's number parsing can
    # depend on the system language), then whole seconds
    for v in "$(awk -v p="$pos" 'BEGIN{printf "%.6f%%", p*100}')" \
             "$(awk -v p="$pos" 'BEGIN{printf "%.6f%%", p*100}' | tr . ,)" \
             "$(awk -v p="$pos" -v l="$len" 'BEGIN{printf "%d", p*l}')"; do
        vlc_get status.xml "command=seek&val=$(urlenc "$v")" >/dev/null
        for k in 1 2 3 4 5 6 7 8 9 10 11 12; do
            sleep 0.5
            st=$(vlc_get status.xml) || continue
            # already rolled over into the next video: close enough
            [ "$(xml_val currentplid "$st")" = "$id" ] || return 0
            p=$(xml_val position "$st")
            if fcmp 'a>=b' "$p" "$lo" && fcmp 'a<=b' "$p" "$hi"; then
                log "resumed ${FILES[$idx]} at $(awk -v p="$pos" 'BEGIN{printf "%.2f%%", p*100}')"
                return 0
            fi
        done
    done
    return 1
}

# ------------------------------ keeping VLC in view ------------------------
vlc_is_front() {   # true if VLC is the front app (or we can't tell)
    if [ "$(uname)" = Darwin ]; then
        command -v lsappinfo >/dev/null || return 1
        lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | grep -q '"VLC"'
    else
        return 0    # Linux kiosk: one desktop, nothing to check
    fi
}

bring_vlc_front() {
    if [ "$(uname)" = Darwin ]; then
        # activates the running VLC and switches to its desktop (Space);
        # never starts a second one, as it's only called while ours runs
        local app; app=$(find_vlc); app="${app%/Contents/MacOS/*}"
        kill -0 "$VLC_PID" 2>/dev/null && [ -d "$app" ] && open -a "$app"
    elif [ -n "$DISPLAY" ] && command -v wmctrl >/dev/null; then
        wmctrl -x -a vlc 2>/dev/null
    fi
}

# ------------------------------ main loop ------------------------------------
run() {
    log "LoopPlayer starting (pid $$)"
    # no sleep, no blank screen while we run
    local awake_pid=""
    if command -v caffeinate >/dev/null; then                       # macOS
        caffeinate -dis -w $$ &
    elif [ "$(uname)" = Linux ]; then
        [ -n "$DISPLAY" ] && command -v xset >/dev/null && xset s off s noblank -dpms 2>/dev/null
        if command -v systemd-inhibit >/dev/null; then
            systemd-inhibit --what=idle:sleep --who=LoopPlayer --why="Video loop playing" \
                sleep 2147483647 >/dev/null 2>&1 &
            awake_pid=$!
        fi
    fi
    trap 'log "LoopPlayer stopping"; stop_vlc; [ -n "$awake_pid" ] && kill "$awake_pid" 2>/dev/null; exit 0' TERM INT HUP

    local resume_fails=0
    while :; do   # outer loop: (re)start VLC
        load_settings
        # folder not there (e.g. external drive not mounted yet): wait for it,
        # without touching the saved playlist
        if [ ! -d "$MEDIA_DIR" ]; then
            log "waiting for video folder: $MEDIA_DIR"
            stop_vlc
            while [ ! -d "$MEDIA_DIR" ]; do sleep 5; load_settings; done
        fi
        # a different folder than last time: brand-new playlist from the start
        if [ -f "$FOLDER_FILE" ] && [ "$(cat "$FOLDER_FILE")" != "$MEDIA_DIR" ]; then
            log "video folder changed to $MEDIA_DIR - starting fresh"
            rm -f "$PLAYLIST"; clear_state
        fi
        printf '%s\n' "$MEDIA_DIR" >"$FOLDER_FILE"
        # reset: forget the place and rebuild the playlist in sorted order
        if [ -f "$RESET_FLAG" ]; then
            rm -f "$RESET_FLAG" "$PLAYLIST"; clear_state; log "loop reset"
        fi
        load_playlist
        if [ ${#FILES[@]} = 0 ]; then
            if ! ls "$MEDIA_DIR/" >/dev/null 2>&1; then
                # macOS 10.15+ blocks background scripts from Desktop,
                # Documents, Downloads and external drives without a prompt
                log "CAN'T READ $MEDIA_DIR: macOS is blocking access. Move the videos to a folder in your home folder (e.g. ~/LoopPlayer/media or ~/Movies), or give /bin/bash Full Disk Access - see README.txt"
            else
                log "no .mp4 or .mov videos in $MEDIA_DIR yet - waiting"
            fi
            while [ ${#FILES[@]} = 0 ]; do sleep 30; load_playlist; done
        fi
        load_state
        rm -f "$RESTART_FLAG"
        stop_vlc
        start_vlc || { sleep 10; continue; }
        if goto_pos "$S_IDX" "$S_POS"; then
            resume_fails=0
        else
            # don't fall through and overwrite the saved place with a wrong
            # one: restart VLC and try again, a few times
            resume_fails=$((resume_fails+1))
            if [ $resume_fails -lt 3 ]; then
                log "could not resume ${FILES[$S_IDX]} (try $resume_fails) - trying again"
                sleep 5; continue
            fi
            # still no luck: that file is probably unplayable. Carry on from
            # the next one, and let VLC play whatever it can.
            log "giving up on ${FILES[$S_IDX]} - carrying on from the next video"
            resume_fails=0
            S_IDX=$(( (S_IDX+1) % ${#FILES[@]} )); S_POS=0
            save_state "$S_IDX" "${FILES[$S_IDX]}" 0 "$S_LOOPS" 0 0
            goto_pos "$S_IDX" 0
        fi

        local idx=$S_IDX last_idx=$S_IDX last_pos=$S_POS loops=$S_LOOPS
        local st state plid pos tm len move fs fails=0 still=0 paused=0 tick=0 fs_tries=0 behind=0
        while :; do   # inner loop: watch VLC
            sleep "$POLL"
            tick=$((tick+1))

            [ -f "$RESET_FLAG" ] && break    # handled at the top of the outer loop
            if [ -f "$RESTART_FLAG" ]; then rm -f "$RESTART_FLAG"; log "restart requested"; break; fi
            if ! kill -0 "$VLC_PID" 2>/dev/null; then log "VLC is gone - restarting it"; break; fi

            # one request + one awk per check: state, item, position, and
            # whether the position went backwards / didn't move since last time
            st=$(vlc_get status.xml | awk -F'[<>]' -v last="$last_pos" '
                $2=="state"{s=$3} $2=="currentplid"{id=$3} $2=="position"{p=$3}
                $2=="time"{t=$3} $2=="length"{l=$3} $2=="fullscreen"{f=$3}
                END{ if (s=="") exit 1; gsub(",", ".", p); if (p=="") p=0; if (f=="") f="unknown"
                     print s, id, p, t+0, l+0, (p+0 < last+0 ? "back" : (p+0 == last+0 ? "same" : "fwd")), f }')
            if [ -z "$st" ]; then
                fails=$((fails+1))
                [ $fails -ge $STALL_LIMIT ] && { log "VLC not answering - restarting it"; break; }
                continue
            fi
            fails=0
            set -- $st; state=$1; plid=$2; pos=$3; tm=$4; len=$5; move=$6; fs=$7

            # fell out of fullscreen (Esc, double-click, a display change)?
            # put it back. If VLC doesn't confirm after 3 tries, stop
            # trying until VLC is next restarted, so it can't flicker.
            if [ "$FULLSCREEN" = 1 ] && [ "$state" = playing ]; then
                if [ "$fs" = false ] && [ $fs_tries -lt 3 ]; then
                    fs_tries=$((fs_tries+1))
                    vlc_get status.xml "command=fullscreen" >/dev/null
                    bring_vlc_front
                    log "VLC was not fullscreen - putting it back (try $fs_tries)"
                    [ $fs_tries = 3 ] && log "fullscreen not confirmed - not trying again until VLC restarts"
                elif [ "$fs" = true ]; then
                    fs_tries=0
                fi
            fi
            # every minute: VLC hidden behind another app or on another
            # desktop (Space) for two checks in a row? bring it back
            if [ "$KEEP_FRONT" = 1 ] && [ $((tick % 6)) = 0 ]; then
                if vlc_is_front; then behind=0
                else
                    behind=$((behind+1))
                    [ $behind -ge 2 ] && { behind=0; bring_vlc_front; log "VLC was not in front - brought it back"; }
                fi
            fi

            if [ "$state" = playing ] || [ "$state" = paused ]; then
                if ! index_of_id "$plid"; then
                    refresh_ids; index_of_id "$plid" || continue
                fi
                idx=$FOUND_IDX
                # one full pass of the playlist done?
                if [ "$idx" -lt "$last_idx" ] || { [ "$idx" = "$last_idx" ] && [ "$move" = back ]; }; then
                    loops=$((loops+1)); log "loop $loops finished"
                fi
                # frozen picture / stuck decoder?
                if [ "$state" = playing ] && [ "$idx" = "$last_idx" ] && [ "$move" = same ]; then
                    still=$((still+1))
                    [ $still -ge $STALL_LIMIT ] && { log "playback stuck - restarting VLC"; still=0; break; }
                else
                    still=0
                fi
                # paused (stray key press, remote, mouse click)? un-pause after a minute
                if [ "$state" = paused ]; then
                    paused=$((paused+1))
                    if [ $paused -ge $PAUSE_LIMIT ]; then
                        paused=0; vlc_get status.xml "command=pl_forceresume" >/dev/null
                        log "was paused for a minute - playing again"
                    fi
                else
                    paused=0
                fi
                # (nothing to write while paused)
                if [ "$move" != same ] || [ "$idx" != "$last_idx" ]; then
                    save_state "$idx" "${FILES[$idx]}" "$pos" "$loops" "$tm" "$len"
                fi
                last_idx=$idx; last_pos=$pos
            elif [ "$state" = stopped ]; then
                # someone pressed stop: carry on from the saved spot
                still=$((still+1))
                [ $still -ge 2 ] && { still=0; goto_pos "$last_idx" "$last_pos" || break; }
            fi

            # folder vanished (drive unplugged)? go back and wait for it
            [ -d "$MEDIA_DIR" ] || { log "video folder went away"; break; }
            # every 5 minutes: don't let VLC's own messages fill the disk
            if [ $((tick % 30)) = 0 ] && [ -n "$(find "$LOG.vlc" -size +5000k 2>/dev/null)" ]; then
                : >"$LOG.vlc"
            fi
        done
    done
}

status() {
    if read_best_state; then
        local n=0 f
        [ -f "$PLAYLIST" ] && while IFS= read -r f; do
            n=$((n+1)); [ "$f" = "$S_NAME" ] && { S_IDX=$((n-1)); break; }
        done <"$PLAYLIST"
        echo "File:      $S_NAME  (#$((S_IDX+1)) in playlist)"
        echo "Position:  $(awk -v p="$S_POS" 'BEGIN{printf "%.2f%%", p*100}')   (${S_TIME}s of ${S_LEN}s)"
        echo "Loops:     $S_LOOPS completed"
        echo "Saved:     $(ls -l "$STATE_FILE" | awk '{print $6, $7, $8}')"
    else
        echo "No saved position yet."
    fi
    echo
    echo "Folder:    $MEDIA_DIR"
    echo "Subtitles: $([ "$SUBTITLES" = 1 ] && echo on || echo off)    Aspect: ${ASPECT:-auto}    Crop: $( [ -n "$CROP_SIDES" ] && echo "${CROP_SIDES}px each side" || echo "${CROP:-none}")    Subtitle size: ${SUB_SIZE:-100}%    Hardware decoding: $HWDEC"
    echo; echo "Playlist:"
    if [ -f "$PLAYLIST" ]; then
        local n=0 f s
        while IFS= read -r f; do
            n=$((n+1)); s=""; srt=$(sub_for "$f") && s="   [subs: ${srt##*/}]"
            printf '%4d  %s%s\n' "$n" "$f" "$s"
        done <"$PLAYLIST"
    fi
}

case "$1" in
    run)     run ;;
    reset)   touch "$RESET_FLAG"
             echo "Reset requested: playback goes back to the first file and the loop count to 0." ;;
    restart) touch "$RESTART_FLAG"; echo "Restart requested." ;;
    status)  status
             [ "$2" = wait ] && { echo; read -n 1 -s -r -p "Press any key to close."; } ;;
    stop|start)
        if [ "$(uname)" = Darwin ]; then
            plist="$HOME/Library/LaunchAgents/com.loopplayer.agent.plist"
            launchctl unload "$plist" 2>/dev/null
            [ "$1" = start ] && launchctl load "$plist"
        else
            systemctl --user "$1" loopplayer.service
        fi
        [ "$1" = stop ] && { sleep 2; pkill -f "http-port=$PORT" 2>/dev/null; }
        echo "LoopPlayer: $1 done." ;;
    set)     [ -n "$2" ] || { echo "usage: $0 set KEY VALUE"; exit 1; }
             set_setting "$2" "$3"; echo "$2=$3" ;;
    *)       echo "usage: $0 run|stop|start|reset|restart|status|set KEY VALUE"; exit 1 ;;
esac
