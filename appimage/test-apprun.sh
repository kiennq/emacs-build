#!/usr/bin/env bash
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/usr/bin" "$root/usr/share/emacs/32.0.50/etc" \
    "$root/usr/share/emacs/32.0.50/lisp" \
    "$root/usr/libexec/emacs/32.0.50/x86_64-pc-linux-gnu"

for program in emacs emacsclient; do
    cat > "$root/usr/bin/$program" <<'EOF'
#!/bin/sh
printf '%s' "${0##*/}"
printf ' <%s>' "$@"
printf '\n'
EOF
    chmod +x "$root/usr/bin/$program"
done

launcher="$(dirname "$0")/AppRun"
jit_options="(setq native-comp-driver-options (list \"-B$root/usr/libexec/emacs-jit/bin/\" \"-B$root/usr/lib/gcc/x86_64-linux-gnu/14/\"))"
actual="$(APPDIR="$root" ARGV0=emacsclient "$launcher" --eval '(+ 1 2)')"
[[ "$actual" == 'emacsclient <--eval> <(+ 1 2)>' ]] || {
    echo "Client dispatch failed: $actual" >&2
    exit 1
}

actual="$(APPDIR="$root" ARGV0="$root/bin/emacsclient" "$launcher" --version)"
[[ "$actual" == 'emacsclient <--version>' ]] || {
    echo "Client symlink dispatch failed: $actual" >&2
    exit 1
}

actual="$(APPDIR="$root" ARGV0=emacs.AppImage "$launcher" --client 'file name')"
[[ "$actual" == 'emacsclient <file name>' ]] || {
    echo "Client option failed: $actual" >&2
    exit 1
}

actual="$(APPDIR="$root" ARGV0=emacs.AppImage "$launcher" --daemon)"
[[ "$actual" == "emacs <--eval> <$jit_options> <--fg-daemon>" ]] || {
    echo "Foreground daemon dispatch failed: $actual" >&2
    exit 1
}

actual="$(APPDIR="$root" ARGV0=emacs.AppImage "$launcher" --batch)"
[[ "$actual" == "emacs <--eval> <$jit_options> <--batch>" ]] || {
    echo "Emacs dispatch failed: $actual" >&2
    exit 1
}

cat > "$root/usr/bin/x86_64-linux-gnu-gcc-14" <<'EOF'
#!/bin/sh
printf '%s\n' "$COMPILER_PATH" "$LIBRARY_PATH" "$1"
EOF
chmod +x "$root/usr/bin/x86_64-linux-gnu-gcc-14"
driver="$(dirname "$0")/jit-gcc"
actual="$(APPDIR="$root" "$driver" --version)"
expected="$root/usr/libexec/emacs-jit/bin
$root/usr/lib/gcc/x86_64-linux-gnu/14:$root/usr/lib
--version"
[[ "$actual" == "$expected" ]] || {
    echo "JIT driver dispatch failed: $actual" >&2
    exit 1
}

echo "AppRun dispatch passed"
