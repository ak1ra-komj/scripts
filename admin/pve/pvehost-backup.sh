#!/usr/bin/env bash
# Back up Proxmox VE host configuration into a separate ZFS dataset.

set -o errexit -o nounset

readonly DEFAULT_BACKUP_DIR="/var/backups/pvehost"
readonly BACKUP_DIR="${PVEHOST_BACKUP_DIR:-${DEFAULT_BACKUP_DIR}}"
readonly RETENTION_DAYS="${PVEHOST_BACKUP_RETENTION_DAYS:-30}"

BACKUP_PATHS=(
    /etc/apt
    /etc/pve
    /etc/lvm
    /etc/modprobe.d
    /etc/network/interfaces
    /etc/network/interfaces.d
    /etc/vzdump.conf
    /etc/sysctl.conf
    /etc/resolv.conf
    /etc/ksmtuned.conf
    /etc/hosts
    /etc/hostname
    /etc/fstab
    /etc/default/grub
    /etc/kernel/cmdline
    /etc/modules
    /etc/cron.d
    /etc/cron.daily
    /etc/cron.hourly
    /etc/cron.monthly
    /etc/cron.weekly
    /etc/crontab
    /etc/aliases
    /etc/apcupsd
)

if ((EUID != 0)); then
    echo "pvehost-backup: must run as root" >&2
    exit 1
fi
if [[ ! "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    echo "pvehost-backup: PVEHOST_BACKUP_RETENTION_DAYS must be an integer" >&2
    exit 1
fi
if [[ ! -f /etc/pve/.version ]]; then
    echo "pvehost-backup: /etc/pve (pmxcfs) is not mounted" >&2
    exit 1
fi

umask 077
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

if [[ "$(findmnt -n -o TARGET --target "${BACKUP_DIR}" 2>/dev/null || true)" == "/" ]]; then
    echo "pvehost-backup: warning: ${BACKUP_DIR} is on the root filesystem" >&2
    echo "pvehost-backup: set PVEHOST_BACKUP_DIR to a separate dataset" >&2
fi

existing=()
for path in "${BACKUP_PATHS[@]}"; do
    [[ -e "${path}" ]] && existing+=("${path}")
done
if ((${#existing[@]} == 0)); then
    echo "pvehost-backup: no paths found" >&2
    exit 1
fi

host="$(hostname)"
backup="${BACKUP_DIR}/${host}-$(date +%F.%s).tar.gz"
tar -C / -czf "${backup}" "${existing[@]#/}"
(cd "${BACKUP_DIR}" && sha256sum "$(basename "${backup}")" >"$(basename "${backup}").sha256")
printf 'Backup: %s (%s)\n' "${backup}" "$(du -h "${backup}" | cut -f1)"

while IFS= read -r old; do
    rm -f -- "${old}" "${old}.sha256"
done < <(find "${BACKUP_DIR}" -maxdepth 1 -type f -name "${host}-*.tar.gz" -mtime "+${RETENTION_DAYS}")
