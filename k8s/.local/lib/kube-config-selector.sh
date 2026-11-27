#!/usr/bin/env bash
# Must be sourced so KUBECONFIG is set in the current shell.
# Example ~/.bash_aliases entry (after `just stow k8s`):
#   test -r "${HOME}/.local/lib/kube-config-selector.sh" && {
#       alias kc='source "${HOME}/.local/lib/kube-config-selector.sh"'
#   }

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cat >&2 <<'EOF'
kube-config-selector.sh must be sourced so KUBECONFIG is set in the current shell.

Add this to ~/.bash_aliases or ~/.bashrc:

  test -r "${HOME}/.local/lib/kube-config-selector.sh" && {
      alias kc='source "${HOME}/.local/lib/kube-config-selector.sh"'
  }

Then reload the shell (or source ~/.bash_aliases) and run: kc
EOF
    exit 1
fi

_kc() {
    local PS3="Select a Kubernetes cluster by index: "
    local REPLY clusters kubeconfig
    mapfile -t clusters < <(
        cd "${HOME}/.kube" && find . -type f -name '*.conf' | sort
    )
    ((${#clusters[@]})) || {
        echo "No *.conf files under ~/.kube" >&2
        return 1
    }

    select kubeconfig in "${clusters[@]}"; do
        [[ -n "${kubeconfig}" ]] || {
            echo "invalid selection" >&2
            continue
        }
        export KUBECONFIG="${HOME}/.kube/${kubeconfig#./}"
        printf 'KUBECONFIG=%s\n' "${KUBECONFIG}"
        return
    done
}
_kc
unset -f _kc
