#!/bin/bash

function write_help () {
    printf "Usage: ./emacs-build-linux.sh [--version|-v <emacs_version>]
                              [--commit|-c <emacs_commit_hash>]
                              [--src|-s <emacs_src_dir>]
                              [--dest|-d <pkg_dest_dir>]
                              [-?|-h|--help]
                              [<build_flags>]\n"
}

emacs_pkg_version="0.0.0.0"
emacs_commit_hash=""
emacs_build_flags=""
emacs_dest_dir="$(pwd)"
emacs_src_dir="$(pwd)"

while test -n "$*"; do
    case $1 in
        --version|-v) shift; emacs_pkg_version="$1";;
        --commit|-c) shift; emacs_commit_hash="$1";;
        --dest|-d) shift; emacs_dest_dir="$(readlink -f $1)";;
        --src|-s) shift; emacs_src_dir="$(readlink -f $1)";;
        -?|-h|--help) write_help; exit 0;;
        *) emacs_build_flags="$emacs_build_flags $1";;
    esac
    shift
done

# override commit hash from pkg_version if not set
emacs_commit_hash=${emacs_commit_hash:-$(echo $emacs_pkg_version | awk -F. '{print $4}')}

echo emacs_src_dir=$emacs_src_dir
echo emacs_dest_dir=$emacs_dest_dir
echo emacs_pkg_version=$emacs_pkg_version
echo emacs_commit_hash=$emacs_commit_hash
echo emacs_build_flags=$emacs_build_flags

cd $emacs_src_dir

render_libs="libtiff-dev librsvg2-dev libxpm-dev libjpeg-dev libpng-dev libgif-dev libwebp-dev libxaw7-dev libharfbuzz-dev"

sudo apt update
sudo apt install -y gcc
gcc_major="$(gcc -dumpfullversion -dumpversion | cut -d. -f1)"
libgccjit_package="libgccjit-${gcc_major}-dev"
sudo apt install -y dpkg-dev autoconf make texinfo binutils file pkg-config libxml2-dev \
     $render_libs libgnutls28-dev libncurses-dev libsystemd-dev "$libgccjit_package" \
     libxt-dev \
     libtree-sitter-dev curl

./autogen.sh

arch=$(dpkg-architecture -q DEB_HOST_ARCH)
pkg_name=emacs-dev_${emacs_commit_hash}_$(dpkg-architecture -q DEB_HOST_MULTIARCH).deb
deb_dir=$(pwd)/deb_pkg
mkdir -p $deb_dir/usr/local/

echo arch=$arch
echo deb_dir=$deb_dir
echo pkg_name=$pkg_name

export LDFLAGS="${LDFLAGS} -lpthread"
./configure CFLAGS="-O2 -fno-semantic-interposition -g $CFLAGS" \
            --prefix=/usr/local/ \
            --with-included-regex --with-native-compilation \
            --with-small-ja-dic --with-x-toolkit=lucid --with-xwidgets $emacs_build_flags \
            --with-sound=no --without-gpm --without-dbus \
            --without-pop --without-mailutils --without-gsettings \
            --with-all

echo "Initial make"
make -j$((`nproc` * 2))
if [ $? -ne 0 ]; then
    exit -1
fi

echo "Make install"
make install-strip DESTDIR=$deb_dir

elf_files=()
while IFS= read -r -d '' file_path; do
    case "$(file -b "$file_path")" in
        ELF*) elf_files+=("$file_path");;
    esac
done < <(find "$deb_dir/usr/local/bin" "$deb_dir/usr/local/libexec" \
              -type f ! -name '*.eln' -print0)

if [ "${#elf_files[@]}" -eq 0 ]; then
    echo "No ELF binaries found under staged /usr/local/bin or /usr/local/libexec" >&2
    exit 1
fi

shlibdeps_dir=$(mktemp -d)
mkdir -p "$shlibdeps_dir/debian"
cat > "$shlibdeps_dir/debian/control" << EOF
Source: emacs-dev

Package: emacs-dev
Architecture: $arch
Description: GNU Emacs
EOF

if ! shlibs_output=$(cd "$shlibdeps_dir" && \
                     dpkg-shlibdeps -O "${elf_files[@]}"); then
    rm -rf -- "$shlibdeps_dir"
    echo "dpkg-shlibdeps failed while generating shared-library dependencies" >&2
    exit 1
fi
rm -rf -- "$shlibdeps_dir"

shlibs_depends="${shlibs_output#shlibs:Depends=}"
if [ "$shlibs_depends" = "$shlibs_output" ] || [ -z "$shlibs_depends" ]; then
    echo "dpkg-shlibdeps produced no shlibs:Depends output" >&2
    exit 1
fi

# create control file
echo "Create deb package"
mkdir -p $deb_dir/DEBIAN

cat > $deb_dir/DEBIAN/control << EOF
Package: emacs-dev
Version: $emacs_pkg_version
Architecture: $arch
Maintainer: www.gnu.org/software/emacs/
Description: GNU Emacs
Depends: $shlibs_depends
EOF

dpkg-deb --build -z9 --root-owner-group $deb_dir $emacs_dest_dir/$pkg_name
