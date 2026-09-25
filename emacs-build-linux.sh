#!/usr/bin/env bash

set -euo pipefail

write_help() {
    cat <<'EOF'
Usage: ./emacs-build-linux.sh --repo <emacs_repository>
                              --commit <emacs_revision>
                              [--version <release_version>]
                              [--dest <appimage_destination>]
                              [-h|--help]
                              [<configure_options>...]
If --version is omitted, EMACS_PKG_VERSION is used.
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emacs_repo=""
emacs_commit=""
emacs_hash=""
emacs_version="${EMACS_PKG_VERSION:-}"
dest_dir="$PWD"
configure_options=()

while (($#)); do
    case "$1" in
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
        --version|-v)
            (($# >= 2)) || fail "$1 requires a value"
            emacs_version="$2"
            shift 2
            ;;
        --dest|-d)
            (($# >= 2)) || fail "$1 requires a value"
            dest_dir="$2"
            shift 2
            ;;
        -h|--help)
            write_help
            exit 0
            ;;
        --manifest|-m)
            fail "unsupported Flatpak option: $1"
            ;;
        --with-*|--without-*|--enable-*|--disable-*)
            configure_options+=("$1")
            shift
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -n "$emacs_repo" ]] || fail "--repo is required"
[[ -n "$emacs_commit" && "$emacs_commit" != -* ]] ||
    fail "--commit must be a Git revision"
[[ "$emacs_version" =~ ^[0-9A-Za-z._+-]+$ ]] ||
    fail "--version or EMACS_PKG_VERSION must be a filename-safe version"

mkdir -p "$dest_dir"
dest_dir="$(cd "$dest_dir" && pwd)"
source_dir="$script_dir/git/emacs"
tree_sitter_dir="$script_dir/build/tree-sitter-packages"
tree_sitter_prefix="$script_dir/build/tree-sitter-prefix"
app_dir="$script_dir/build/emacs.AppDir"
output_dir="$script_dir/build/appimage-output"
tool_dir="$script_dir/build/appimage-tools"
elevate=()
if ((EUID != 0)); then
    command -v sudo >/dev/null || fail "sudo is needed to install build dependencies"
    elevate=(sudo)
fi

install_dependencies() {
    "${elevate[@]}" apt-get update
    "${elevate[@]}" apt-get install -y --no-install-recommends \
        autoconf automake binutils build-essential ca-certificates curl file \
        gcc-14 git libgccjit-14-dev libgif-dev libgnutls28-dev \
        libharfbuzz-dev libjpeg-dev libncurses-dev libpng-dev \
        librsvg2-dev libtiff-dev libwebp-dev \
        libxaw7-dev libxml2-dev libxpm-dev libxt-dev patchelf pkg-config texinfo
}

install_tree_sitter() {
    local base=https://snapshot.ubuntu.com/ubuntu/20260925T000000Z/pool/universe/t/tree-sitter
    local runtime=libtree-sitter0.25_0.25.9-7_amd64.deb
    local development=libtree-sitter-dev_0.25.9-7_amd64.deb
    local unpacked="$tree_sitter_dir/extracted"

    mkdir -p "$tree_sitter_dir" "$tree_sitter_prefix/lib/pkgconfig"
    curl --fail --location --silent --show-error --retry 2 \
        --output "$tree_sitter_dir/$runtime" "$base/$runtime"
    curl --fail --location --silent --show-error --retry 2 \
        --output "$tree_sitter_dir/$development" "$base/$development"
    printf '%s  %s\n' \
        b640c8bc15a56a5765900051b52be7349295e79135dbbc0a7c04bb9d07728ac3 \
        "$tree_sitter_dir/$runtime" |
        sha256sum --check
    printf '%s  %s\n' \
        62cbe7b5891517d8bada5713bd4e34da8bf30176aff83598f94a549d5de8d5b9 \
        "$tree_sitter_dir/$development" |
        sha256sum --check

    dpkg-deb -x "$tree_sitter_dir/$runtime" "$unpacked"
    dpkg-deb -x "$tree_sitter_dir/$development" "$unpacked"
    install -Dm644 "$unpacked/usr/lib/x86_64-linux-gnu/libtree-sitter.so.0.25" \
        "$tree_sitter_prefix/lib/libtree-sitter.so.0.25"
    ln -sfn libtree-sitter.so.0.25 "$tree_sitter_prefix/lib/libtree-sitter.so.0"
    ln -sfn libtree-sitter.so.0 "$tree_sitter_prefix/lib/libtree-sitter.so"
    install -Dm644 "$unpacked/usr/include/tree_sitter/api.h" \
        "$tree_sitter_prefix/include/tree_sitter/api.h"
    sed -e "s|^prefix=.*|prefix=$tree_sitter_prefix|" \
        -e "s|^libdir=.*|libdir=$tree_sitter_prefix/lib|" \
        "$unpacked/usr/lib/x86_64-linux-gnu/pkgconfig/tree-sitter.pc" \
        > "$tree_sitter_prefix/lib/pkgconfig/tree-sitter.pc"

    export PKG_CONFIG_PATH="$tree_sitter_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="$tree_sitter_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    [[ "$(pkg-config --modversion tree-sitter)" == 0.25.9 ]] ||
        fail "Emacs would not build against prebuilt Tree-sitter 0.25.9"
    grep -Fq '#define TREE_SITTER_LANGUAGE_VERSION 15' \
        "$tree_sitter_prefix/include/tree_sitter/api.h" ||
        fail "prebuilt Tree-sitter does not support parser ABI 15"
}

prepare_source() {
    local checkout_ref=FETCH_HEAD
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

    if ! git -C "$source_dir" fetch --filter=tree:0 --no-tags --force origin "$emacs_commit"; then
        git -C "$source_dir" rev-parse --verify -q "${emacs_commit}^{commit}" >/dev/null ||
            fail "cannot fetch or check out Git revision $emacs_commit"
        echo "warning: using locally available revision $emacs_commit" >&2
        checkout_ref="$emacs_commit"
    fi
    git -C "$source_dir" checkout --detach --force "$checkout_ref"
    git -C "$source_dir" clean -ffdx
    emacs_hash="$(git -C "$source_dir" rev-parse --short=8 HEAD)"
}

download_linuxdeploy() {
    local tool="$tool_dir/linuxdeploy.AppImage"
    mkdir -p "$tool_dir"
    curl --fail --location --silent --show-error --retry 2 \
        --output "$tool" \
        https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage
    printf '%s  %s\n' \
        c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d \
        "$tool" | sha256sum --check
    chmod 755 "$tool"
}

install_jit_driver() {
    local gcc_libdir="$app_dir/usr/lib/gcc/x86_64-linux-gnu/14"
    local jit_bin="$app_dir/usr/libexec/emacs-jit"
    local file

    install -Dm755 /usr/bin/x86_64-linux-gnu-gcc-14 \
        "$app_dir/usr/bin/x86_64-linux-gnu-gcc-14"
    install -Dm755 /usr/libexec/gcc/x86_64-linux-gnu/14/collect2 \
        "$app_dir/usr/libexec/gcc/x86_64-linux-gnu/14/collect2"
    install -Dm755 /usr/libexec/gcc/x86_64-linux-gnu/14/liblto_plugin.so \
        "$app_dir/usr/libexec/gcc/x86_64-linux-gnu/14/liblto_plugin.so"
    for file in crtbeginS.o crtendS.o libgcc.a libgcc_s.so; do
        install -Dm644 "/usr/lib/gcc/x86_64-linux-gnu/14/$file" \
            "$gcc_libdir/$file"
    done
    for file in crti.o crtn.o libc_nonshared.a; do
        install -Dm644 "/usr/lib/x86_64-linux-gnu/$file" \
            "$gcc_libdir/$file"
    done
    cat > "$gcc_libdir/libc.so" <<'EOF'
OUTPUT_FORMAT(elf64-x86-64)
GROUP ( libc.so.6 libc_nonshared.a AS_NEEDED ( /lib64/ld-linux-x86-64.so.2 ) )
EOF

    install -Dm755 "$script_dir/appimage/jit-gcc" \
        "$jit_bin/x86_64-linux-gnu-gcc-14"
    for file in as ld; do
        install -Dm755 "$(readlink -f "/usr/bin/$file")" "$jit_bin/bin/$file"
    done
}

install_dependencies
install_tree_sitter
prepare_source
download_linuxdeploy

cd "$source_dir"
./autogen.sh
CC=gcc-14 CFLAGS="-O2 -fno-semantic-interposition" ./configure \
    --prefix=/usr \
    --with-native-compilation --with-tree-sitter --with-x-toolkit=lucid \
    --with-sound=no --without-gpm --without-dbus \
    --without-pop --without-mailutils --without-gsettings \
    "${configure_options[@]}"
make -j"$(nproc)"

rm -rf -- "$app_dir" "$output_dir"
mkdir -p "$app_dir" "$output_dir"
make install-strip DESTDIR="$app_dir"
install_jit_driver
for package in gcc-14 gcc-14-base libgcc-14-dev binutils binutils-common libc6-dev; do
    install -Dm644 "/usr/share/doc/$package/copyright" \
        "$app_dir/usr/share/doc/$package/copyright"
done
install -Dm644 "$tree_sitter_dir/extracted/usr/share/doc/libtree-sitter0.25/copyright" \
    "$app_dir/usr/share/doc/libtree-sitter0.25/copyright"
install -Dm644 "$script_dir/appimage/site-start.el" \
    "$app_dir/usr/share/emacs/site-lisp/site-start.el"

dump_file="$(find "$app_dir/usr/libexec/emacs" -name 'emacs-*.pdmp' -print -quit)"
[[ -n "$dump_file" ]] || fail "Emacs did not install its portable dump"
dump_link="$(realpath --relative-to="$app_dir/usr/bin" "$dump_file")"
ln -s "$dump_link" "$app_dir/usr/bin/emacs.pdmp"
ln -s "$dump_link" "$app_dir/usr/bin/$(readlink "$app_dir/usr/bin/emacs").pdmp"

desktop_file="$app_dir/usr/share/applications/emacs.desktop"
icon_file="$app_dir/usr/share/icons/hicolor/128x128/apps/emacs.png"
[[ -f "$desktop_file" && -f "$icon_file" ]] ||
    fail "Emacs did not install its desktop file and icon"

(
    cd "$output_dir"
    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 \
        LINUXDEPLOY_OUTPUT_VERSION="$emacs_version" "$tool_dir/linuxdeploy.AppImage" \
        --appdir="$app_dir" \
        --deploy-deps-only="$app_dir/usr" \
        --deploy-deps-only="$app_dir/usr/libexec/emacs-jit/bin" \
        --deploy-deps-only="$app_dir/usr/libexec/gcc/x86_64-linux-gnu/14" \
        --desktop-file="$desktop_file" \
        --icon-file="$icon_file" \
        --custom-apprun="$script_dir/appimage/AppRun" \
        --output appimage
)

unset PKG_CONFIG_PATH LD_LIBRARY_PATH
build_triplet="$(APPDIR="$app_dir" "$app_dir/AppRun" --batch -Q \
    --eval '(princ system-configuration)')"
[[ "$build_triplet" =~ ^[0-9A-Za-z._+-]+$ ]] ||
    fail "invalid Emacs build triplet: $build_triplet"
bundle="$dest_dir/emacs_${emacs_hash}_${build_triplet}.AppImage"

shopt -s nullglob
produced=("$output_dir"/*.AppImage)
((${#produced[@]} == 1)) ||
    fail "expected one AppImage, found ${#produced[@]} in $output_dir"
mv -f -- "${produced[0]}" "$bundle"

APPIMAGE_EXTRACT_AND_RUN=1 "$bundle" --batch -Q \
    --eval '(unless (and (native-comp-available-p)
                         (treesit-available-p)
                         (= (treesit-library-abi-version) 15)
                         (libxml-available-p)
                         (string-match-p "MPS" system-configuration-features)
                         (string-match-p "RSVG" system-configuration-features)
                         (string-match-p "LUCID" system-configuration-features))
               (kill-emacs 1))' \
    --eval '(let ((source (make-temp-file "appimage-native-" nil ".el"
                                         ";;; -*- lexical-binding: t; -*-\n(defun appimage-native-smoke (x) (+ x 1))"))
                  output)
               (unwind-protect
                   (progn (setq output (native-compile source))
                          (load output nil t)
                          (unless (= (appimage-native-smoke 41) 42)
                            (error "Native compilation returned the wrong result")))
                 (delete-file source)
                 (when output (delete-file output))))'

APPIMAGE_EXTRACT_AND_RUN=1 "$bundle" --client --version
echo "Created $bundle"
