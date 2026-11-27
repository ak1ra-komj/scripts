#!/usr/bin/env bash
# Show ReplicaSet image/revision history for Deployments.

set -o errexit -o nounset -o pipefail

usage() {
    cat <<'EOF'
Usage: kube-deploy-history.sh [-n NAMESPACE | -A] [DEPLOYMENT...]

Show ReplicaSet image history for deployments.

Options:
  -n, --namespace NAMESPACE  Namespace (default: current context)
  -A, --all-namespaces       All namespaces; cannot be combined with names
  -h, --help                 Show this help
EOF
}

warn() { printf 'warning: %s\n' "$*" >&2; }

namespace=""
all_namespaces=false
while (($#)); do
    case "${1}" in
        -h | --help)
            usage
            exit 0
            ;;
        -n | --namespace)
            namespace="${2:?-n requires a namespace}"
            shift 2
            ;;
        -A | --all-namespaces)
            all_namespaces=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf 'unknown option: %s\n' "${1}" >&2
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done
deployments=("${@}")

if [[ "${all_namespaces}" == true && -n "${namespace}" ]]; then
    printf 'error: -n and -A are mutually exclusive\n' >&2
    exit 2
fi
if [[ "${all_namespaces}" == true && ${#deployments[@]} -gt 0 ]]; then
    printf 'error: -A cannot be combined with deployment names\n' >&2
    exit 2
fi

for cmd in kubectl jq column; do
    command -v "${cmd}" >/dev/null || {
        printf 'missing command: %s\n' "${cmd}" >&2
        exit 1
    }
done

if [[ "${all_namespaces}" == false ]]; then
    if [[ -z "${namespace}" ]]; then
        namespace="$(kubectl config view --minify -o jsonpath='{..namespace}')"
        namespace="${namespace:-default}"
    fi
    kubectl_args=(-n "${namespace}")
else
    kubectl_args=(--all-namespaces)
fi

rs_json="$(kubectl get replicasets.apps "${kubectl_args[@]}" -o json)"

if ! jq -e '.items | length > 0' >/dev/null <<<"${rs_json}"; then
    warn "no ReplicaSets found"
    exit 0
fi

for deployment in "${deployments[@]}"; do
    jq -e --arg d "${deployment}" '
        any(.items[];
            any(.metadata.ownerReferences[]?;
                .kind == "Deployment" and .name == $d))
    ' >/dev/null <<<"${rs_json}" ||
        warn "no ReplicaSets found for deployment '${deployment}'"
done

printf 'NAMESPACE\tDEPLOYMENT\tREVISION\tCREATED\tREPLICASET\tDESIRED\tCURRENT\tIMAGES\n'
jq -r --args '
    .items
    | map(
        . as $rs
        | ([.metadata.ownerReferences[]?
            | select(.kind == "Deployment")
            | .name] | first) as $deploy
        | select($deploy != null)
        | select(($ARGS.positional | length) == 0
                 or ($ARGS.positional | index($deploy)))
        | . + {deploy: $deploy}
      )
    | sort_by(.metadata.namespace, .deploy, .metadata.creationTimestamp)
    | .[]
    | [
        .metadata.namespace,
        .deploy,
        (.metadata.annotations["deployment.kubernetes.io/revision"] // "N/A"),
        .metadata.creationTimestamp,
        .metadata.name,
        (.spec.replicas // 0),
        (.status.replicas // 0),
        ([.spec.template.spec.containers[].image]
         + [(.spec.template.spec.initContainers // [])[].image]
         | join(","))
      ]
    | @tsv
' -- "${deployments[@]}" <<<"${rs_json}" | column -t -s $'\t'
