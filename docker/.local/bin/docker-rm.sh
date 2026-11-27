#!/usr/bin/env bash
# Delete Docker images whose REPOSITORY:TAG matches an extended regex.

set -o errexit -o nounset

usage() {
    cat <<EOF
usage: ${0##*/} [-v] [--apply] PATTERN

Delete images whose REPOSITORY:TAG matches extended regex PATTERN.
For dangling images:    docker image prune
For stopped containers: docker container prune

  -v, --invert-match   select images that do NOT match PATTERN
      --apply          actually delete (default: dry run)
EOF
    exit "${1:-0}"
}

apply=false
invert=false
pattern=

while (($#)); do
    case "${1}" in
        --apply) apply=true ;;
        -v | --invert-match) invert=true ;;
        -h | --help) usage ;;
        -*) usage 1 >&2 ;;
        *) pattern="${1}" ;;
    esac
    shift
done

if [[ -z "${pattern}" ]]; then
    usage 1 >&2
fi

docker info >/dev/null

if [[ "${invert}" == true ]]; then
    mapfile -t images < <(docker image ls --format '{{.Repository}}:{{.Tag}}' |
        grep -v ':<none>$' | grep -vE -- "${pattern}")
else
    mapfile -t images < <(docker image ls --format '{{.Repository}}:{{.Tag}}' |
        grep -v ':<none>$' | grep -E -- "${pattern}")
fi

if ((${#images[@]} == 0)); then
    echo "no images selected for pattern: ${pattern}" >&2
    exit 0
fi

printf '%s\n' "${images[@]}"
if [[ "${apply}" == true ]]; then
    docker image rm "${images[@]}"
else
    echo "[dry-run] use --apply to delete ${#images[@]} image(s)" >&2
fi
