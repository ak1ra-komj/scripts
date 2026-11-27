#!/usr/bin/env bash
# Map whole disks to their /dev/disk/by-id WWN and ATA/SCSI paths.

set -o errexit -o nounset

readonly BY_ID=/dev/disk/by-id

[[ -d "${BY_ID}" ]] || {
    echo "${BY_ID} not found" >&2
    exit 1
}

shopt -s nullglob

declare -A wwn=()
declare -A ata=()

for link in "${BY_ID}"/wwn-*; do
    [[ -L "${link}" ]] || continue
    name="${link##*/}"
    case "${name}" in *-part[0-9]*) continue ;; esac
    dev=$(readlink -f -- "${link}") || continue
    [[ -n "${dev}" ]] || continue
    [[ -n "${wwn[${dev}]:-}" ]] || wwn[${dev}]="${link}"
done

for link in "${BY_ID}"/ata-* "${BY_ID}"/scsi-*; do
    [[ -L "${link}" ]] || continue
    name="${link##*/}"
    case "${name}" in *-part[0-9]*) continue ;; esac
    dev=$(readlink -f -- "${link}") || continue
    [[ -n "${dev}" ]] || continue
    [[ -n "${ata[${dev}]:-}" ]] || ata[${dev}]="${link}"
done

declare -A devices=()
for dev in "${!wwn[@]}" "${!ata[@]}"; do
    # Exclude ZFS zvols (/dev/zdN) and optical drives (/dev/srN).
    case "${dev}" in /dev/zd[0-9]* | /dev/sr[0-9]*) continue ;; esac
    devices[${dev}]=1
done

print_table() {
    printf 'DEVICE\tWWN-ID\tATA/SCSI-ID\n'
    for dev in "${!devices[@]}"; do
        printf '%s\t%s\t%s\n' \
            "${dev}" "${wwn[${dev}]:--}" "${ata[${dev}]:--}"
    done | sort
}

if command -v column >/dev/null 2>&1; then
    print_table | column -t -s $'\t'
else
    print_table
fi
