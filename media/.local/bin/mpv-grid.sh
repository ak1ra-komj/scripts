#!/usr/bin/env bash
# Play videos in a grid of mpv windows.

set -o errexit -o nounset

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
usage: ${0##*/} [OPTIONS] [VIDEO ...]
Play videos in a grid of mpv windows; with no VIDEO, pick random files under .
  -m, --monitor INDEX     monitor index from xrandr (default: 0)
  -l, --layout ROWSxCOLS  grid layout, e.g. 2x2 (default: 2x2)
  -h, --help              show this help
EOF
    exit "${1:-0}"
}

monitor=0
layout=2x2
command -v getopt >/dev/null || die "missing command: getopt"
args=$(getopt -o hm:l: -l help,monitor:,layout: -n "${0##*/}" -- "$@") || usage 2 >&2
eval set -- "${args}"
while (($#)); do
    case "${1}" in
        -h | --help) usage 0 ;;
        -m | --monitor) monitor="${2}" ;;
        -l | --layout) layout="${2}" ;;
        --) break ;;
    esac
    shift 2
done
shift

[[ "${monitor}" =~ ^[0-9]+$ ]] || die "invalid monitor: ${monitor}"
[[ "${layout}" =~ ^([1-9][0-9]*)x([1-9][0-9]*)$ ]] || die "invalid layout: ${layout}"
rows=$((10#${BASH_REMATCH[1]}))
cols=$((10#${BASH_REMATCH[2]}))
monitor=$((10#${monitor}))

for cmd in mpv xrandr; do
    command -v "${cmd}" >/dev/null || die "missing command: ${cmd}"
done

area=$(xrandr --listmonitors | awk -v n="${monitor}" '
    $1 == n ":" { split($3, g, /[x+\/]/); print g[5], g[6], g[1], g[3]; f = 1 }
    END { exit !f }
') || die "monitor ${monitor} not found (is DISPLAY set?)"
read -r x y width height <<<"${area}"

cell_width=$((width / cols))
cell_height=$((height / rows))
((cell_width > 0 && cell_height > 0)) || die "layout ${layout} does not fit monitor ${monitor}"

max=$((rows * cols))
if (($# > 0)); then
    videos=("$@")
else
    mapfile -d '' -t videos < <(
        find . -type f \( \
            -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' -o \
            -iname '*.mov' -o -iname '*.flv' -o -iname '*.wmv' -o -iname '*.webm' \
            \) -print0 | shuf -z -n "${max}"
    )
    ((${#videos[@]} > 0)) || die "no video files found under ."
fi

if ((${#videos[@]} < max)); then
    echo "warning: ${#videos[@]} video(s) for ${max} cell(s)" >&2
fi

for ((i = 0; i < ${#videos[@]} && i < max; i++)); do
    geometry="${cell_width}x${cell_height}+$((x + (i % cols) * cell_width))+$((y + (i / cols) * cell_height))"
    WAYLAND_DISPLAY='' mpv --geometry="${geometry}" --no-border -- "${videos[${i}]}" &
done
