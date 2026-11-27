#!/usr/bin/env bash
# Report TLS secrets whose leaf certificate expires within DAYS days.

set -o errexit -o nounset

days="${1:-30}"
[[ "${days}" =~ ^[0-9]+$ ]] || {
    echo "usage: ${0##*/} [DAYS]" >&2
    exit 2
}
days=$((10#${days}))

secrets=$(kubectl get secrets --all-namespaces --field-selector type=kubernetes.io/tls \
    -o go-template='{{range .items}}{{.metadata.namespace}} {{.metadata.name}} {{index .data "tls.crt"}}{{"\n"}}{{end}}') || exit 1

found=0
while read -r namespace name crt; do
    [[ -n "${crt}" ]] || continue
    pem=$(base64 -d <<<"${crt}" 2>/dev/null) || continue

    # -checkend exits non-zero when the certificate expires within DAYS.
    openssl x509 -noout -checkend "$((days * 86400))" <<<"${pem}" >/dev/null 2>&1 && continue

    subject=$(openssl x509 -noout -subject -nameopt RFC2253 <<<"${pem}" 2>/dev/null)
    issuer=$(openssl x509 -noout -issuer -nameopt RFC2253 <<<"${pem}" 2>/dev/null)
    not_after=$(openssl x509 -noout -enddate <<<"${pem}" 2>/dev/null)

    printf '=== %s/%s ===\nSubject: %s\nIssuer : %s\nNot after: %s\n\n' \
        "${namespace}" "${name}" "${subject#subject=}" "${issuer#issuer=}" "${not_after#notAfter=}"
    found=1
done <<<"${secrets}"

((found)) || echo "No TLS certificates expiring within ${days} days." >&2
