#!/usr/bin/env bash
# Summarise conntrack entries per source or destination IP.
# Usage: conntrack-count.sh [tcp|udp] [src|dst]

set -o errexit -o nounset -o pipefail

proto="${1:-tcp}"
peer="${2:-src}"
case "${proto}:${peer}" in
    tcp:src | tcp:dst | udp:src | udp:dst) ;;
    *)
        echo "usage: ${0##*/} [tcp|udp] [src|dst]" >&2
        exit 1
        ;;
esac

for c in conntrack gawk; do
    command -v "${c}" >/dev/null || {
        echo "missing: ${c}" >&2
        exit 1
    }
done

conntrack -L -p "${proto}" | gawk -v proto="${proto}" -v peer="${peer}" '
    BEGIN {
        ns = split(proto == "tcp" ? "SYN_SENT SYN_RECV ESTABLISHED FIN_WAIT TIME_WAIT CLOSE_WAIT LAST_ACK CLOSE" : "UNREPLIED ASSURED DEFAULT", states, " ")
        for (i = 1; i <= ns; i++) known[states[i]] = 1
    }
    $1 == proto {
        match($0, "(^| )" peer "=[^ ]+")
        ip = substr($0, RSTART, RLENGTH)
        sub(/^[^=]*=/, "", ip)
        if (ip == "") next

        if (proto == "tcp") state = $4
        else if ($0 ~ /\[UNREPLIED\]/) state = "UNREPLIED"
        else if ($0 ~ /\[ASSURED\]/) state = "ASSURED"
        else state = "DEFAULT"

        if (!(state in known)) {
            states[++ns] = state
            known[state] = 1
        }
        count[ip, state]++
        total[ip]++
    }
    END {
        PROCINFO["sorted_in"] = "@val_num_desc"
        iw = length(peer == "src" ? "SRC_IP" : "DST_IP")
        w = proto == "tcp" ? 11 : 9
        for (ip in total) if (length(ip) > iw) iw = length(ip)
        printf "%-*s", iw, (peer == "src" ? "SRC_IP" : "DST_IP") > "/dev/stderr"
        for (i = 1; i <= ns; i++) printf " %*s", w, states[i] > "/dev/stderr"
        printf " %5s\n", "TOTAL" > "/dev/stderr"
        for (ip in total) {
            printf "%-*s", iw, ip
            for (i = 1; i <= ns; i++) printf " %*d", w, count[ip, states[i]] + 0
            printf " %5d\n", total[ip]
        }
    }'
