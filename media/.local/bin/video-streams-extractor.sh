#!/usr/bin/env bash
#
# Extract streams from media files, one output file per stream.

set -o errexit -o nounset

kind=subtitle
force=false
status=0

usage() {
    echo "usage: ${0##*/} [-t TYPE] [-f] FILE..." >&2
    echo "  TYPE: subtitle (default), audio, video, all" >&2
    exit "${1:-2}"
}

while getopts ':t:fh' opt; do
    case $opt in
        t) kind=$OPTARG ;;
        f) force=true ;;
        h) usage 0 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
(($#)) || usage

case $kind in
    subtitle) selector=s ;;
    audio) selector=a ;;
    video) selector=V ;;
    all) selector= ;;
    *)
        echo "error: invalid type: $kind" >&2
        exit 2
        ;;
esac
for cmd in ffmpeg ffprobe; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "error: $cmd not found" >&2
        exit 1
    }
done

extract() {
    local input=$1 rows index codec ctype lang dir base stem out ext coder spec
    local -a probe_args=()

    [[ -f $input ]] || {
        echo "error: no such file: $input" >&2
        status=1
        return
    }
    dir=$(dirname -- "$input")
    base=$(basename -- "$input")
    stem=${base%.*}
    [[ -n $stem ]] || stem=$base

    [[ -z $selector ]] || probe_args=(-select_streams "$selector")
    if ! rows=$(ffprobe -v error "${probe_args[@]}" \
        -show_entries stream=index,codec_name,codec_type:stream_tags=language \
        -of csv=p=0 -- "$input"); then
        echo "error: ffprobe failed: $input" >&2
        status=1
        return
    fi
    [[ -n $rows ]] || {
        echo "no $kind streams: $input" >&2
        return
    }

    while IFS=, read -r index codec ctype lang; do
        [[ -n $index ]] || continue
        lang=${lang:-und}
        case $lang in *[!A-Za-z0-9_-]*) lang=und ;; esac
        case $ctype:$codec in
            video:*) spec=mkv:copy ;;
            audio:*) spec=mka:copy ;;
            subtitle:ass | subtitle:ssa) spec=ass:copy ;;
            subtitle:webvtt) spec=vtt:copy ;;
            subtitle:hdmv_pgs_subtitle) spec=sup:copy ;;
            subtitle:subrip) spec=srt:copy ;;
            subtitle:mov_text | subtitle:text) spec=srt:srt ;;
            subtitle:*) spec=mkv:copy ;;
            *) continue ;;
        esac
        ext=${spec%:*}
        coder=${spec#*:}

        out=$dir/$stem.$lang.$index.$ext
        if [[ -e $out && $force != true ]]; then
            echo "skip (exists): $out" >&2
            continue
        fi
        if ffmpeg -nostdin -hide_banner -loglevel error -y \
            -i "$input" -map "0:$index" -c "$coder" "$out"; then
            echo "$out"
        else
            echo "error: failed to extract stream $index from $input" >&2
            status=1
        fi
    done <<<"$rows"
}

for input in "$@"; do
    extract "$input"
done
exit "$status"
