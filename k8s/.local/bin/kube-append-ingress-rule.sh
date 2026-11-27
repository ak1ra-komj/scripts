#!/usr/bin/env bash
# Append suffix-modified rules to a Kubernetes Ingress JSON file.

set -o errexit -o nounset

usage() {
    echo "usage: ${0##*/} [-i] FILE [SUFFIX]" >&2
    exit "${1:-2}"
}

in_place=false
case "${1:-}" in
    -i | --in-place)
        in_place=true
        shift
        ;;
    -h | --help) usage 0 ;;
    --) shift ;;
    -*)
        echo "unknown option: ${1}" >&2
        usage
        ;;
esac

file="${1:-}"
suffix="${2:--delta}"
[[ -n "${file}" && -f "${file}" ]] || {
    echo "not a file: ${file:-<missing>}" >&2
    exit 1
}

# shellcheck disable=SC2016
filter='
def add_suffix($suffix):
    if startswith("*.") then .
    elif contains(".") then
        capture("^(?<subdomain>[^.]+)\\.(?<domain>.+)$")
        | "\(.subdomain)\($suffix).\(.domain)"
    else "\(.)\($suffix)"
    end;

(if .kind != "Ingress" then error("expected an Ingress, got \(.kind // "unknown")") else . end)
| (if .spec.rules then
    .spec.rules |= . + [
        .[] | select(.host != null and (.host | startswith("*.") | not))
        | .host |= add_suffix($suffix)
    ]
   else . end)
| (if .spec.tls then
    .spec.tls |= map(if .hosts then .hosts |= (. + [.[] | add_suffix($suffix)] | unique) else . end)
   else . end)
'

if [[ "${in_place}" == true ]]; then
    tmp=$(mktemp "${file}.XXXXXX")
    trap 'rm -f "${tmp}"' EXIT
    jq --indent 4 --arg suffix "${suffix}" "${filter}" "${file}" >"${tmp}"
    chmod --reference="${file}" "${tmp}"
    mv "${tmp}" "${file}"
else
    jq --indent 4 --arg suffix "${suffix}" "${filter}" "${file}"
fi
