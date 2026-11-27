#!/usr/bin/env bash
# Wrapper around ansible.builtin.copy for installing scripts on a remote host.

set -o errexit -o nounset

readonly PROGRAM="${0##*/}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

usage() {
    cat <<EOF
usage: ${PROGRAM} [ANSIBLE_OPTIONS...] HOST SCRIPT... [-- ANSIBLE_OPTIONS...]

Copy individual Unix scripts from this repository to HOST.
SCRIPT paths are relative to the repository root.
Extra options (e.g. -K, -u USER, --check) are passed through to ansible;
use -- to pass arbitrary ansible options verbatim.

Environment:
  DESTDIR   remote target directory (default: /usr/local/bin)
EOF
}

die() {
    echo "${PROGRAM}: error: $*" >&2
    exit 1
}

host=""
declare -a scripts=()
declare -a ansible_args=(-b)

while (($# > 0)); do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            ansible_args+=("$@")
            break
            ;;
        -i | --inventory | -u | --user | -e | --extra-vars | -T | --timeout | \
            -f | --forks | -l | --limit | -c | --connection | \
            --become-user | --become-method | --private-key | \
            --ssh-common-args | --ssh-extra-args | \
            --vault-password-file | --vault-id)
            if (($# < 2)); then
                die "option requires an argument: $1"
            fi
            ansible_args+=("$1" "$2")
            shift 2
            ;;
        -*)
            ansible_args+=("$1")
            shift
            ;;
        *)
            if [[ -z "${host}" ]]; then
                host="$1"
            else
                scripts+=("$1")
            fi
            shift
            ;;
    esac
done

if [[ -z "${host}" ]] || ((${#scripts[@]} == 0)); then
    usage >&2
    exit 1
fi

dest="${DESTDIR:-/usr/local/bin}"

for script in "${scripts[@]}"; do
    case "/${script}/" in
        //* | */../*) die "script must be a relative path within the repository: ${script}" ;;
    esac
    src="${REPO_ROOT}/${script}"
    if [[ ! -f "${src}" ]]; then
        die "unknown script: ${script}"
    fi
    mode="0644"
    if [[ -x "${src}" ]]; then
        mode="0755"
    fi
    echo "install ${script} -> ${host}:${dest}/${script##*/}"
    ansible "${host}" "${ansible_args[@]}" -m ansible.builtin.copy \
        -a "src=${src} dest=${dest}/${script##*/} mode=${mode} owner=root group=root"
done
