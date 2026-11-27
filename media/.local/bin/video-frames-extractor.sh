#!/bin/sh
#
# Extract a non-black frame from the end of each video to <name>.last.png.

set -eu

tail=3
status=0

usage() {
    echo "usage: ${0##*/} [-s SECONDS] FILE..." >&2
    exit "${1:-2}"
}

err() {
    echo "error: $*" >&2
    status=1
}

while getopts ':s:h' opt; do
    case $opt in
        s) tail=$OPTARG ;;
        h) usage 0 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ "$#" -gt 0 ] || usage

awk -v t="$tail" 'BEGIN { exit !(t ~ /^[0-9]*[.]?[0-9]+$/ && t + 0 > 0) }' ||
    {
        echo "error: invalid -s value: $tail" >&2
        exit 2
    }
command -v ffmpeg >/dev/null 2>&1 || {
    echo "error: ffmpeg not found" >&2
    exit 1
}

for input in "$@"; do
    if [ ! -f "$input" ]; then
        err "no such file: $input"
        continue
    fi

    dir=$(dirname -- "$input")
    base=$(basename -- "$input")
    stem=${base%.*}
    [ -n "$stem" ] || stem=$base
    out=$dir/$stem.last.png

    if ! log=$(ffmpeg -nostdin -hide_banner -nostats -loglevel info \
        -sseof "-$tail" -i "$input" -map 0:V:0 -an \
        -vf 'blackdetect=d=0.1:pix_th=0.1' -f null - 2>&1); then
        err "failed to analyze: $input"
        continue
    fi

    # blackdetect times are relative to the seek point. If the last black
    # interval reaches the end, extract the frame just before it.
    if ! back=$(printf '%s\n' "$log" | awk -v t="$tail" '
        /black_start:/ {
            s = $0; sub(/.*black_start:/, "", s); sub(/ .*/, "", s)
            e = $0; sub(/.*black_end:/,   "", e); sub(/ .*/, "", e)
        }
        END {
            if (e == "" || e < t - 0.5) { print "0.1"; exit }
            if (s < 0.05) exit 1
            b = t - s + 0.1
            if (b < 0.1) b = 0.1
            printf "%.2f\n", b
        }'); then
        err "last ${tail}s of $input are black; use a larger -s value"
        continue
    fi

    if ffmpeg -nostdin -hide_banner -nostats -loglevel error -y \
        -sseof "-$back" -i "$input" -map 0:V:0 -frames:v 1 -update 1 "$out"; then
        echo "$out"
    else
        err "failed to extract a frame: $input"
    fi
done

exit "$status"
