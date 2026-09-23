#!/usr/bin/env bash

set -euo pipefail

write_help() {
    cat <<'EOF'
Usage: ./emacs-build-linux.sh --version <emacs_version>
                              --repo <emacs_repository>
                              --commit <emacs_commit_hash>
                              [--dest <bundle_destination>]
                              [--manifest <flatpak_manifest>]
                              [-h|--help]
                              [<build_options>...]
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emacs_version=""
emacs_repo=""
emacs_commit=""
dest_dir="$PWD"
manifest="$script_dir/flatpak/io.github.kiennq.emacs.json"
build_options=()

while (($#)); do
    case "$1" in
        --version|-v)
            (($# >= 2)) || fail "$1 requires a value"
            emacs_version="$2"
            shift 2
            ;;
        --repo|-r)
            (($# >= 2)) || fail "$1 requires a value"
            emacs_repo="$2"
            shift 2
            ;;
        --commit|-c)
            (($# >= 2)) || fail "$1 requires a value"
            emacs_commit="$2"
            shift 2
            ;;
        --dest|-d)
            (($# >= 2)) || fail "$1 requires a value"
            dest_dir="$2"
            shift 2
            ;;
        --manifest|-m)
            (($# >= 2)) || fail "$1 requires a value"
            manifest="$2"
            shift 2
            ;;
        -h|--help)
            write_help
            exit 0
            ;;
        *)
            build_options+=("$1")
            shift
            ;;
    esac
done

[[ -n "$emacs_version" ]] || fail "--version is required"
[[ "$emacs_version" =~ ^[0-9A-Za-z._+-]+$ ]] ||
    fail "version contains unsupported filename characters"
[[ -n "$emacs_repo" ]] || fail "--repo is required"
[[ "$emacs_commit" =~ ^[0-9a-fA-F]{40}$ ]] ||
    fail "--commit must be a full 40-character Git commit hash"
[[ -f "$manifest" ]] || fail "Flatpak manifest not found: $manifest"

case "$(uname -m)" in
    x86_64|amd64) ;;
    *) fail "only x86_64 Linux builds are supported" ;;
esac

mkdir -p "$dest_dir"
dest_dir="$(cd "$dest_dir" && pwd)"
manifest="$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")"
build_manifest="$manifest"
temporary_manifest=""

source_dir="$script_dir/git/emacs"
build_dir="$script_dir/build/flatpak"
state_dir="$script_dir/build/flatpak-state"
repo_dir="$script_dir/pkg/flatpak-repo"
app_id="io.github.kiennq.emacs"
runtime_repo="https://flathub.org/repo/flathub.flatpakrepo"

install_flatpak_tools() {
    local packages=()
    local elevate=()

    command -v flatpak >/dev/null 2>&1 || packages+=(flatpak)
    command -v flatpak-builder >/dev/null 2>&1 || packages+=(flatpak-builder)
    command -v python3 >/dev/null 2>&1 || packages+=(python3)
    ((${#packages[@]})) || return 0

    command -v apt-get >/dev/null 2>&1 ||
        fail "install ${packages[*]} and rerun this script"

    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 ||
            fail "sudo is required to install ${packages[*]}"
        elevate=(sudo)
    fi

    "${elevate[@]}" apt-get update
    "${elevate[@]}" apt-get install -y "${packages[@]}"
}

prepare_emacs_source() {
    local fetched_commit

    mkdir -p "$(dirname "$source_dir")"

    if [[ -d "$source_dir/.git" ]]; then
        git -C "$source_dir" remote set-url origin "$emacs_repo"
    else
        [[ ! -e "$source_dir" ]] ||
            fail "$source_dir exists but is not a Git checkout"
        mkdir "$source_dir"
        git -C "$source_dir" init
        git -C "$source_dir" remote add origin "$emacs_repo"
    fi

    git -C "$source_dir" fetch --filter=tree:0 --no-tags --force origin "$emacs_commit"
    fetched_commit="$(git -C "$source_dir" rev-parse 'FETCH_HEAD^{commit}')"
    [[ "${fetched_commit,,}" == "${emacs_commit,,}" ]] ||
        fail "requested commit was not fetched from $emacs_repo"

    git -C "$source_dir" checkout --detach --force "$fetched_commit"
    git -C "$source_dir" clean -ffdx
}

prepare_manifest() {
    ((${#build_options[@]})) || return 0

    temporary_manifest="$(
        mktemp --suffix=.json "$(dirname "$manifest")/.emacs-flatpak-manifest.XXXXXX"
    )"
    python3 - "$manifest" "$temporary_manifest" "${build_options[@]}" <<'PY'
import json
import sys

source, destination, *build_options = sys.argv[1:]
with open(source, encoding="utf-8") as source_file:
    manifest = json.load(source_file)

for module in manifest["modules"]:
    if module.get("name") == "emacs":
        module.setdefault("config-opts", []).extend(build_options)
        break
else:
    raise SystemExit("Emacs module not found in Flatpak manifest")

with open(destination, "w", encoding="utf-8", newline="\n") as destination_file:
    json.dump(manifest, destination_file, indent=2)
    destination_file.write("\n")
PY
    build_manifest="$temporary_manifest"
}

cleanup() {
    [[ -z "$temporary_manifest" ]] || rm -f -- "$temporary_manifest"
}

trap cleanup EXIT

install_flatpak_tools
prepare_emacs_source
prepare_manifest

mkdir -p "$state_dir" "$repo_dir"
flatpak remote-add --user --if-not-exists flathub "$runtime_repo"

flatpak-builder \
    --user \
    --assumeyes \
    --ccache \
    --force-clean \
    --install-deps-from=flathub \
    --repo="$repo_dir" \
    --state-dir="$state_dir" \
    "$build_dir" \
    "$build_manifest"

flatpak build --runtime "$build_dir" emacs --batch -Q \
    --eval '(unless (and (native-comp-available-p)
                         (treesit-available-p)
                         (libxml-available-p)
                         (string-match-p "MPS" system-configuration-features))
               (kill-emacs 1))' \
    --eval '(let ((source (make-temp-file "flatpak-native-" nil ".el"
                                         ";;; -*- lexical-binding: t; -*-\n(defun flatpak-native-smoke (x) (+ x 1))"))
                  output)
               (unwind-protect
                   (progn (setq output (native-compile source))
                          (load output nil t)
                          (unless (= (flatpak-native-smoke 41) 42)
                            (error "Native compilation returned the wrong result")))
                 (delete-file source)
                 (when output (delete-file output))))'

build_triplet="$(flatpak build --runtime "$build_dir" emacs --batch -Q \
    --eval '(princ system-configuration)')"
[[ "$build_triplet" =~ ^[0-9A-Za-z._+-]+$ ]] ||
    fail "invalid Emacs build triplet: $build_triplet"
bundle="$dest_dir/emacs_${emacs_commit:0:8}_${build_triplet}.flatpak"

rm -f -- "$bundle"
flatpak build-bundle \
    --arch=x86_64 \
    --runtime-repo="$runtime_repo" \
    "$repo_dir" \
    "$bundle" \
    "$app_id"

echo "Created $bundle"
