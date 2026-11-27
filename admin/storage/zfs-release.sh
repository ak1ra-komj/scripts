#!/usr/bin/env bash

set -o errexit -o nounset

rootfs="${1:?Usage: $0 <rootfs>}"
case "${rootfs}" in
    */)
        echo "rootfs cannot end with a slash: ${rootfs}" >&2
        exit 1
        ;;
esac

snapshots="$(zfs list -Hr -t snapshot -o name "${rootfs}")"
while IFS= read -r snapshot; do
    [[ -n "${snapshot}" ]] || continue
    holds="$(zfs holds -H "${snapshot}")"
    while IFS=$'\t' read -r _ tag _; do
        [[ -n "${tag}" ]] || continue
        printf "Releasing hold '%s' from '%s'\n" "${tag}" "${snapshot}"
        zfs release "${tag}" "${snapshot}"
    done <<<"${holds}"
done <<<"${snapshots}"
