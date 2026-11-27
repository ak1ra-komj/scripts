#!/usr/bin/env bash
# Inspect X.509 certificates from a PEM bundle or a TLS endpoint.
# Usage: x509-inspect.sh FILE|HOST[:PORT]|https://HOST[:PORT]

set -o errexit -o nounset -o pipefail

export LC_ALL=C

readonly PROGRAM="${0##*/}"
readonly TIMEOUT=10
tmpdir=

die() {
    printf '%s: error: %s\n' "${PROGRAM}" "$*" >&2
    exit 1
}

warn() {
    printf '%s: warning: %s\n' "${PROGRAM}" "$*" >&2
}

usage() {
    local exit_code="${1:-0}" output_fd=1
    ((exit_code == 0)) || output_fd=2
    cat >&"${output_fd}" <<EOF
Usage: ${PROGRAM} FILE|HOST[:PORT]|https://HOST[:PORT]

Inspect one or more certificates from a PEM file, or the chain served by
a TLS endpoint. File paths and bare hostnames are both accepted.

Examples:
  ${PROGRAM} https://example.com/
  ${PROGRAM} example.com:8443
  ${PROGRAM} /etc/letsencrypt/live/example.com/fullchain.pem
EOF
    exit "${exit_code}"
}

cn_or_dn() {
    local dn="$1" cn
    if [[ "${dn}" =~ (^|[,+])CN=((\\.|[^,+])+)([,+]|$) ]]; then
        cn="${BASH_REMATCH[2]}"
        printf '%s' "${cn//\\,/,}"
    else
        printf '%s' "${dn}"
    fi
}

extract_certificates() {
    local input="$1" outdir="$2"
    awk -v outdir="${outdir}" '
        /-----BEGIN CERTIFICATE-----/ {
            if (!inside) {
                count++
                file = sprintf("%s/cert-%03d.pem", outdir, count)
                inside = 1
            }
        }
        inside { print > file }
        /-----END CERTIFICATE-----/ && inside { close(file); inside = 0 }
        END { if (count == 0 || inside) exit 1 }
    ' "${input}"
}

inspect_certificate() {
    local cert="$1"
    local text serial fingerprint subject_dn issuer_dn not_before not_after
    local subject issuer kind key_description san_output san_names

    text=$(openssl x509 -in "${cert}" -noout \
        -serial -subject -issuer -startdate -enddate \
        -fingerprint -sha256 -nameopt RFC2253 -dateopt iso_8601 -text) ||
        die "failed to parse certificate: ${cert}"

    serial=$(sed -n 's/^serial=//p' <<<"${text}" | tr '[:lower:]' '[:upper:]')
    fingerprint=$(sed -n 's/^[^=]*Fingerprint=//p' <<<"${text}")
    fingerprint=${fingerprint//:/}
    subject_dn=$(sed -n 's/^subject=//p' <<<"${text}")
    issuer_dn=$(sed -n 's/^issuer=//p' <<<"${text}")
    not_before=$(sed -n 's/^notBefore=//p' <<<"${text}")
    not_after=$(sed -n 's/^notAfter=//p' <<<"${text}")

    [[ -n "${serial}" && -n "${fingerprint}" ]] ||
        die "certificate is missing required metadata: ${cert}"

    subject=$(cn_or_dn "${subject_dn}")
    issuer=$(cn_or_dn "${issuer_dn}")

    san_output=$(openssl x509 -in "${cert}" -noout -ext subjectAltName 2>/dev/null || true)
    san_names=$(sed -n '2,$p' <<<"${san_output}" |
        tr -d ' ' | tr ',' '\n' |
        sed -n -E 's/^(DNS|IPAddress):(.+)$/\2/p' | paste -sd, -)

    # The public-key description comes from the human-readable text dump; it
    # is the only portable way to get both algorithm and curve/size.
    key_description=$(awk '
        /Public Key Algorithm:/ { alg = $NF }
        /Public-Key: \(/ {
            bits = $0
            sub(/.*\(/, "", bits)
            sub(/ bit.*/, "", bits)
        }
        /NIST CURVE:/ { curve = $NF }
        /ASN1 OID:/ { oid = $NF }
        END {
            if (alg ~ /id-ecPublicKey/) {
                if (curve == "") curve = oid
                print "ECDSA " (curve == "" ? "unknown-curve" : curve)
            } else if (alg ~ /rsaEncryption/) {
                print "RSA " (bits == "" ? "unknown" : bits)
            } else if (alg ~ /rsassa-pss/) {
                print "RSA-PSS " (bits == "" ? "unknown" : bits)
            } else if (alg ~ /Ed25519/) {
                print "Ed25519"
            } else if (alg ~ /Ed448/) {
                print "Ed448"
            } else if (alg ~ /dsaEncryption/) {
                print "DSA " (bits == "" ? "unknown" : bits)
            } else {
                print (alg == "" ? "unknown" : alg)
            }
        }
    ' <<<"${text}")

    if grep -Eq 'CA:[[:space:]]*TRUE' <<<"${text}"; then
        if [[ "${subject_dn}" == "${issuer_dn}" ]]; then
            kind="Root CA Certificate"
        else
            kind="Intermediate CA Certificate"
        fi
    else
        kind="TLS Certificate"
    fi

    printf 'X.509v3 %s (%s)\n' "${kind}" "${key_description}"
    printf '  Subject:     %s\n' "${subject}"
    [[ -z "${san_names}" ]] || printf '  SAN:         %s\n' "${san_names}"
    printf '  Issuer:      %s\n' "${issuer}"
    printf '  Valid from:  %s\n' "${not_before/ /T}"
    printf '          to:  %s\n' "${not_after/ /T}"
    printf '  Serial:      %s\n' "${serial}"
    printf '  SHA-256:     %s\n\n' "${fingerprint}"
}

main() {
    case "${1:-}" in
        -h | --help) usage 0 ;;
    esac
    [[ "$#" -eq 1 ]] || usage 2
    local target="$1"
    local source status=0 host host_part port connect s_client_args

    for cmd in openssl awk sed tr timeout mktemp grep; do
        command -v "${cmd}" >/dev/null 2>&1 || die "required command not found: ${cmd}"
    done

    if [[ "${target}" != *://* && ! -e "${target}" ]]; then
        case "${target}" in
            /* | ./* | ../* | *.pem | *.crt | *.cer)
                die "file not found: ${target}"
                ;;
        esac
    fi
    if [[ -e "${target}" ]]; then
        [[ -f "${target}" ]] || die "not a regular file: ${target}"
        [[ -r "${target}" ]] || die "cannot read file: ${target}"
    fi

    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/${PROGRAM}.XXXXXX") ||
        die "could not create temporary directory"
    trap 'rm -rf "${tmpdir}"' EXIT

    if [[ -f "${target}" ]]; then
        source="${target}"
    else
        case "${target}" in
            https://*) host_part="${target#https://}" ;;
            *://*) die "only https:// URLs are supported" ;;
            *) host_part="${target}" ;;
        esac
        host_part="${host_part%%/*}"
        host_part="${host_part%%\?*}"
        host_part="${host_part%%#*}"
        [[ -n "${host_part}" ]] || die "target hostname is empty"
        [[ "${host_part}" != *@* ]] || die "URL user information is not supported"

        port=443
        if [[ "${host_part}" =~ ^\[([^]]+)\](:([0-9]+))?$ ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[3]:-443}"
            connect="[${host}]:${port}"
        elif [[ "${host_part}" =~ ^([^:]+):([0-9]+)$ ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            connect="${host}:${port}"
        elif [[ "${host_part}" != *:* ]]; then
            host="${host_part}"
            connect="${host}:${port}"
        else
            die "invalid target; use HOST[:PORT] or [IPv6]:PORT"
        fi
        [[ "${port}" =~ ^[0-9]+$ ]] || die "port is out of range: ${port}"
        ((10#${port} >= 1 && 10#${port} <= 65535)) ||
            die "port is out of range: ${port}"

        s_client_args=(-connect "${connect}" -showcerts)
        if [[ "${host}" != *:* && ! "${host}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            s_client_args+=(-servername "${host}")
        fi

        source="${tmpdir}/s_client.stdout"
        if timeout --foreground "${TIMEOUT}s" openssl s_client "${s_client_args[@]}" \
            </dev/null >"${source}" 2>"${tmpdir}/s_client.stderr"; then
            status=0
        else
            status=$?
        fi
    fi

    if ! extract_certificates "${source}" "${tmpdir}"; then
        if [[ -f "${target}" ]]; then
            die "no complete PEM certificate found in ${target}"
        fi
        if ((status == 124)); then
            die "TLS connection timed out after ${TIMEOUT}s"
        fi
        [[ ! -s "${tmpdir}/s_client.stderr" ]] || cat "${tmpdir}/s_client.stderr" >&2
        die "no complete PEM certificate was received from ${connect}"
    fi

    if [[ ! -f "${target}" ]] && ((status != 0)); then
        warn "openssl s_client exited with status ${status}; showing certificates received before the failure"
        [[ ! -s "${tmpdir}/s_client.stderr" ]] || cat "${tmpdir}/s_client.stderr" >&2
    fi

    local cert
    for cert in "${tmpdir}"/cert-*.pem; do
        inspect_certificate "${cert}"
    done
}

main "$@"
