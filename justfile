set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Format all shell scripts
fmt:
    shfmt -f . | xargs -r shfmt -w -i 4 -ci

# Lint shell scripts and syntax-check Python
check:
    shfmt -f . | xargs -r shellcheck
    shfmt -f . | xargs -r shfmt -d -i 4 -ci
    python3 -c 'import ast, pathlib; [ast.parse(p.read_text(encoding="utf-8"), str(p)) for p in pathlib.Path(".").rglob("*.py") if not any(part in {".git", ".venv"} for part in p.parts)]'

# List available GNU Stow packages
list-packages:
    @find . -mindepth 2 -maxdepth 2 -type d -name .local -printf '%P\n' | sed 's|/\.local$||' | sort

# Stow selected packages into ${TARGET:-${HOME}}
[positional-arguments]
stow *packages:
    #!/usr/bin/env bash
    set -o errexit -o nounset
    if (($# == 0)); then
        echo "usage: just stow PACKAGE..." >&2
        exit 1
    fi
    for pkg in "$@"; do
        if [[ "${pkg}" == */* || ! -d "${pkg}/.local" ]]; then
            echo "unknown stow package: ${pkg}" >&2
            exit 1
        fi
    done
    target="${TARGET:-${HOME}}"
    mkdir -p "${target}"
    for pkg in "$@"; do
        while IFS= read -r -d '' rel; do
            dst="${target}/${rel}"
            if [[ -L "${dst}" && ! -e "${dst}" ]]; then
                echo "removing broken symlink: ${dst}" >&2
                rm -- "${dst}"
            fi
        done < <(find "${pkg}" -mindepth 1 -printf '%P\0')
    done
    stow --no-folding -R -t "${target}" "$@"

# Unstow selected packages from ${TARGET:-${HOME}}
[positional-arguments]
unstow *packages:
    #!/usr/bin/env bash
    set -o errexit -o nounset
    if (($# == 0)); then
        echo "usage: just unstow PACKAGE..." >&2
        exit 1
    fi
    for pkg in "$@"; do
        if [[ "${pkg}" == */* || ! -d "${pkg}/.local" ]]; then
            echo "unknown stow package: ${pkg}" >&2
            exit 1
        fi
    done
    target="${TARGET:-${HOME}}"
    stow -D -t "${target}" "$@"

# Install selected Unix scripts locally to ${DESTDIR:-/usr/local/bin}
[positional-arguments]
install *scripts:
    #!/usr/bin/env bash
    set -o errexit -o nounset
    if (($# == 0)); then
        echo "usage: just install SCRIPT..." >&2
        exit 1
    fi
    dest="${DESTDIR:-/usr/local/bin}"
    declare -a install_cmd=(install)
    if ! mkdir -p "${dest}" 2>/dev/null || [[ ! -w "${dest}" ]]; then
        sudo mkdir -p "${dest}"
        install_cmd=(sudo install)
    fi
    for script in "$@"; do
        case "/${script}/" in
            //* | */../*)
                echo "script must be a relative path within the repository: ${script}" >&2
                exit 1
                ;;
        esac
        if [[ ! -f "${script}" ]]; then
            echo "unknown script: ${script}" >&2
            exit 1
        fi
        mode="0644"
        if [[ -x "${script}" ]]; then
            mode="0755"
        fi
        "${install_cmd[@]}" -m "${mode}" "${script}" "${dest}/${script##*/}"
    done

# Install selected Unix scripts on a remote host via ansible ad-hoc
[positional-arguments]
install-remote *args:
    ./install/install.sh "$@"

# Install selected PowerShell scripts to %USERPROFILE%\bin
install-windows *scripts:
    test -n "{{scripts}}" || { echo "usage: just install-windows SCRIPT..." >&2; exit 1; }
    powershell.exe -NoProfile -Command 'New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\bin" | Out-Null; Copy-Item -Force -Verbose {{scripts}} "$env:USERPROFILE\bin"'

# List Windows PowerShell scripts
list-windows:
    find pwsh -maxdepth 1 -type f -name '*.ps1' -print | sort
