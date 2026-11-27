#!/usr/bin/env bash
# Run an all-nodes iperf3 mesh inside Kubernetes.
# Usage: kube-iperf3.sh [init|cleanup] [-o DIR] [IPERF3_ARGS...]

set -o errexit -o nounset

readonly SERVER_NS=iperf3-server
readonly CLIENT_NS=iperf3-client
readonly IMAGE=ghcr.io/ak1ra-lab/iperf3
readonly MANAGED_BY=kube-iperf3
readonly TIMEOUT=120s

info() { printf '%s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err() { printf 'error: %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: ${0##*/} [COMMAND] [OPTIONS] [IPERF3_ARGS...]

Commands:
  run       Run every client pod against every server pod (default)
  init      Create the iperf3 namespaces and DaemonSets
  cleanup   Delete the namespaces created by init

Options:
  -o, --output DIR   Result directory for run (default: ./kube-iperf3)
  -h, --help         Show this help
EOF
    exit "${1:-2}"
}

namespace_owned() {
    local ns="$1" owner
    owner=$(kubectl get namespace "${ns}" \
        -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' \
        2>/dev/null) || return 1
    [[ "${owner}" == "${MANAGED_BY}" ]]
}

init() {
    local ns

    for ns in "${SERVER_NS}" "${CLIENT_NS}"; do
        if kubectl get namespace "${ns}" >/dev/null 2>&1 &&
            ! namespace_owned "${ns}"; then
            err "namespace ${ns} exists and is not managed by ${MANAGED_BY}"
            exit 1
        fi
    done

    kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${SERVER_NS}
  labels:
    app.kubernetes.io/managed-by: ${MANAGED_BY}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iperf3-server
  namespace: ${SERVER_NS}
  labels:
    app: iperf3-server
    app.kubernetes.io/managed-by: ${MANAGED_BY}
spec:
  selector:
    matchLabels:
      app: iperf3-server
  template:
    metadata:
      labels:
        app: iperf3-server
    spec:
      containers:
        - name: iperf3-server
          image: ${IMAGE}
          args: ["-s"]
          ports:
            - protocol: TCP
              containerPort: 5201
              name: tcp
            - protocol: UDP
              containerPort: 5201
              name: udp
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${CLIENT_NS}
  labels:
    app.kubernetes.io/managed-by: ${MANAGED_BY}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iperf3-client
  namespace: ${CLIENT_NS}
  labels:
    app: iperf3-client
    app.kubernetes.io/managed-by: ${MANAGED_BY}
spec:
  selector:
    matchLabels:
      app: iperf3-client
  template:
    metadata:
      labels:
        app: iperf3-client
    spec:
      containers:
        - name: iperf3
          image: ${IMAGE}
          command: ["sleep", "infinity"]
EOF

    kubectl -n "${SERVER_NS}" rollout status daemonset/iperf3-server --timeout="${TIMEOUT}"
    kubectl -n "${CLIENT_NS}" rollout status daemonset/iperf3-client --timeout="${TIMEOUT}"
    info "iperf3 resources are running; run '${0##*/} cleanup' when done"
}

cleanup() {
    local ns rc=0

    for ns in "${SERVER_NS}" "${CLIENT_NS}"; do
        kubectl get namespace "${ns}" >/dev/null 2>&1 || continue
        if ! namespace_owned "${ns}"; then
            warn "refusing to delete unmanaged namespace ${ns}"
            rc=1
            continue
        fi
        if ! kubectl delete namespace "${ns}" --wait=true --timeout=60s; then
            warn "failed to delete namespace ${ns}"
            rc=1
        fi
    done
    return "${rc}"
}

run_tests() {
    local out="$1"
    shift
    local file n=0 failed=0
    local -a clients=() servers=()
    local line lines c s cname cnode sip snode rc

    mkdir -p "${out}"
    file="${out}/kube-iperf3.$(date +%F_%H%M%S).$$.txt"

    if ! lines=$(kubectl -n "${CLIENT_NS}" get pods -l app=iperf3-client \
        --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'); then
        err "failed to list iperf3 client pods; run '${0##*/} init' first"
        exit 1
    fi
    while IFS= read -r line; do
        [[ -n "${line}" ]] && clients+=("${line}")
    done <<<"${lines}"

    if ! lines=$(kubectl -n "${SERVER_NS}" get pods -l app=iperf3-server \
        --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.status.podIP}{"\t"}{.spec.nodeName}{"\n"}{end}'); then
        err "failed to list iperf3 server pods; run '${0##*/} init' first"
        exit 1
    fi
    while IFS= read -r line; do
        [[ -n "${line}" ]] && servers+=("${line}")
    done <<<"${lines}"

    ((${#clients[@]})) || {
        err "no running iperf3 client pods; run '${0##*/} init' first"
        exit 1
    }
    ((${#servers[@]})) || {
        err "no running iperf3 server pods; run '${0##*/} init' first"
        exit 1
    }

    for c in "${clients[@]}"; do
        IFS=$'\t' read -r cname cnode <<<"${c}"
        for s in "${servers[@]}"; do
            IFS=$'\t' read -r sip snode <<<"${s}"
            n=$((n + 1))
            printf 'Test %d: %s -> %s (%s)\n' \
                "${n}" "${cnode}" "${snode}" "${sip}" | tee -a "${file}"
            kubectl -n "${CLIENT_NS}" exec "${cname}" -- \
                iperf3 -c "${sip}" "$@" 2>&1 | tee -a "${file}"
            rc="${PIPESTATUS[0]}"
            if ((rc != 0)); then
                warn "test ${n} failed (exit ${rc})"
                printf 'FAILED: exit %d\n' "${rc}" >>"${file}"
                failed=$((failed + 1))
            fi
        done
    done

    info "results: ${file}"
    ((failed == 0)) || exit 1
}

action=run
case "${1:-}" in
    init | --init)
        action=init
        shift
        ;;
    cleanup | --cleanup)
        action=cleanup
        shift
        ;;
    -h | --help) usage 0 ;;
esac

output=./kube-iperf3
while (($#)); do
    case "${1}" in
        -o | --output)
            output="${2:?-o requires a directory}"
            shift 2
            ;;
        -h | --help) usage 0 ;;
        --)
            shift
            break
            ;;
        *) break ;;
    esac
done

case "${action}" in
    init) init ;;
    cleanup) cleanup ;;
    run) run_tests "${output}" "$@" ;;
esac
