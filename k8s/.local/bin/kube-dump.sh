#!/usr/bin/env bash
# Dump listable Kubernetes resources as sanitized JSON manifests.
set -o errexit -o nounset -o pipefail
umask 077

readonly CATTLE_RE='^(?:(?:authz\.cluster|secret\.user|field|lifecycle|listener|workload)\.)?cattle\.io/'
# shellcheck disable=SC2016
readonly FILTER='
  walk(if type == "object" then
      with_entries(select(.key | test($cattle) | not))
    else . end)
  | del(
      .metadata.namespace,
      .metadata.annotations."deployment.kubernetes.io/revision",
      .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
      .metadata.creationTimestamp,
      .metadata.deletionTimestamp,
      .metadata.generation,
      .metadata.managedFields,
      .metadata.resourceVersion,
      .metadata.selfLink,
      .metadata.uid,
      .metadata.ownerReferences,
      .status,
      .spec.clusterIP,
      .spec.clusterIPs
    )
'

info() { printf '%s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err() { printf 'error: %s\n' "$*" >&2; }
die() {
    err "$*"
    exit 1
}

usage() {
    cat <<'EOF'
Usage: kube-dump.sh [-A | NAMESPACE...] [-C] [-f] [-o DIR]

Dump listable Kubernetes resources as sanitized per-object JSON files.

Options:
  -A, --all-namespaces               Dump every namespace
  -C, --include-cluster-resources    Also dump cluster-scoped resources
  -f, --force                        Overwrite existing files
  -o, --output DIR                   Output directory (default: ./kube-dump)
  -h, --help                         Show this help

Secrets are included in plaintext. Output files are mode 0600, directories
0700. The result is a manifest snapshot, not a backup/restore tool.
EOF
}

output=./kube-dump
all=false
cluster=false
force=false

while (($#)); do
    case "${1}" in
        -A | --all-namespaces)
            all=true
            shift
            ;;
        -C | --include-cluster-resources)
            cluster=true
            shift
            ;;
        -f | --force)
            force=true
            shift
            ;;
        -o | --output)
            output="${2:?-o requires a directory}"
            shift 2
            ;;
        -h | --help) usage ;;
        --)
            shift
            break
            ;;
        -*)
            err "unknown option: ${1}"
            usage >&2
            exit 2
            ;;
        *) break ;;
    esac
done

namespaces=("$@")
if [[ "${all}" == true && ${#namespaces[@]} -gt 0 ]]; then
    err "-A cannot be combined with namespace arguments"
    exit 2
fi
if [[ "${all}" == false && ${#namespaces[@]} -eq 0 ]]; then
    ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
    namespaces=("${ns:-default}")
fi

for cmd in kubectl jq; do
    command -v "${cmd}" >/dev/null || die "missing command: ${cmd}"
done
mkdir -p "${output}"

ns_types=()
cluster_types=()
if ! types=$(kubectl api-resources --verbs=list --namespaced=true -o name); then
    die "failed to list namespaced API resources"
fi
while IFS= read -r type; do
    [[ -n "${type}" ]] && ns_types+=("${type}")
done <<<"${types}"

if [[ "${cluster}" == true ]]; then
    if ! types=$(kubectl api-resources --verbs=list --namespaced=false -o name); then
        die "failed to list cluster-scoped API resources"
    fi
    while IFS= read -r type; do
        [[ -n "${type}" ]] && cluster_types+=("${type}")
    done <<<"${types}"
fi

dumped=0
skipped=0
failed=0

dump_item() {
    local ns="$1" type="$2" item="$3"
    local name dir file tmp

    name=$(jq -r '.metadata.name // empty' <<<"${item}")
    [[ -n "${name}" ]] || return 0

    dir="${output}/${ns}/${type}"
    file="${dir}/${name}.json"
    if [[ -e "${file}" && "${force}" == false ]]; then
        skipped=$((skipped + 1))
        return 0
    fi

    mkdir -p "${dir}"
    tmp=$(mktemp "${dir}/.${name}.XXXXXX")
    if jq --arg cattle "${CATTLE_RE}" --indent 2 --sort-keys "${FILTER}" \
        <<<"${item}" >"${tmp}"; then
        mv "${tmp}" "${file}"
        dumped=$((dumped + 1))
    else
        rm -f "${tmp}"
        warn "failed: ${ns}/${type}/${name}"
        failed=$((failed + 1))
    fi
}

dump_list() {
    local ns="$1" type="$2" json item

    if ! json=$(kubectl -n "${ns}" get "${type}" -o json); then
        warn "list failed: ${ns}/${type}"
        failed=$((failed + 1))
        return 0
    fi
    while IFS= read -r item; do
        [[ -n "${item}" ]] || continue
        dump_item "${ns}" "${type}" "${item}"
    done < <(jq -c '.items[]?' <<<"${json}")
}

dump_all_type() {
    local type="$1" json item ns

    if ! json=$(kubectl get "${type}" --all-namespaces -o json); then
        warn "list failed: all-namespaces/${type}"
        failed=$((failed + 1))
        return 0
    fi
    while IFS= read -r item; do
        [[ -n "${item}" ]] || continue
        ns=$(jq -r '.metadata.namespace // "_cluster"' <<<"${item}")
        dump_item "${ns}" "${type}" "${item}"
    done < <(jq -c '.items[]?' <<<"${json}")
}

dump_cluster_type() {
    local type="$1" json item

    if ! json=$(kubectl get "${type}" -o json); then
        warn "list failed: cluster/${type}"
        failed=$((failed + 1))
        return 0
    fi
    while IFS= read -r item; do
        [[ -n "${item}" ]] || continue
        dump_item "_cluster" "${type}" "${item}"
    done < <(jq -c '.items[]?' <<<"${json}")
}

case " ${ns_types[*]} " in
    *" secrets "*) warn "Secrets are dumped in plaintext (files are mode 0600)" ;;
esac

if [[ "${all}" == true ]]; then
    for type in "${ns_types[@]}"; do
        case "${type}" in events | events.*) continue ;; esac
        dump_all_type "${type}"
    done
else
    for ns in "${namespaces[@]}"; do
        if ! kubectl get namespace "${ns}" >/dev/null 2>&1; then
            warn "namespace not found: ${ns}"
            failed=$((failed + 1))
            continue
        fi
        for type in "${ns_types[@]}"; do
            case "${type}" in events | events.*) continue ;; esac
            dump_list "${ns}" "${type}"
        done
    done
fi

if [[ "${cluster}" == true ]]; then
    for type in "${cluster_types[@]}"; do
        dump_cluster_type "${type}"
    done
fi

info "dumped=${dumped} skipped=${skipped} failed=${failed} -> ${output}"
if ((failed > 0)); then
    exit 1
fi
