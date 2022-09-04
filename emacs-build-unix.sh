#!/bin/bash

function write_help () {
    echo "Usage: ./emacs-build-linux.sh --version <emacs_version> [<build_flags>]"
}

emacs_pkg_version="0.0.0.0"
emacs_build_flags=""

while test -n "$*"; do
    case $1 in
        --version) shift; emacs_pkg_version="$1";;
        -?|-h|--help) write_help; exit 0;;
        *) emacs_build_flags="$emacs_build_flags $1";;
    esac
    shift
done

render_libs="librsvg2-dev libxpm-dev libjpeg-dev libpng-dev libgif-dev libgtk-3-dev libharfbuzz-dev"
render_deps=",librsvg2-2,libxpm4,libjpeg9,libgif7,libpng16-16,libgtk-3-0,libharfbuzz0b"

sudo add-apt-repository -y ppa:ubuntu-toolchain-r/ppa
sudo apt update
sudo apt install -y dpkg-dev autoconf make texinfo $render_libs libgnutls28-dev \
     libncurses5-dev libsystemd-dev libjansson-dev libgccjit-10-dev g++-10 gcc-10 libxt-dev \
     libtree-sitter-dev libwebkit2gtk-4.0-dev curl
export CC=/usr/bin/gcc-10 CXX=/usr/bin/gcc-10

./autogen.sh

arch=$(dpkg-architecture -q DEB_BUILD_ARCH)
pkg_name=emacs-dev_${emacs_pkg_version}_$arch
deb_dir=$(pwd)/$pkg_name
mkdir -p $deb_dir/usr/local/

echo arch=$arch
echo deb_dir=$deb_dir
echo pkg_name=$pkg_name

./configure CFLAGS="-O3 -mtune=native -march=native -fomit-frame-pointer" \
            --prefix=/usr/local/ \
            --with-included-regex --with-native-compilation \
            --with-small-ja-dic --with-pgtk --with-xwidgets $emacs_build_flags \
            --with-sound=no --without-gpm --without-dbus \
            --without-pop --without-mailutils --without-gsettings \
            --with-all

make -j$(($(nproc) * 2))
# NOTE: use `checkinstall` will make `make install` hangs.
# See https://github.com/emacs-ng/emacs-ng/issues/364
make install-strip DESTDIR=$deb_dir

# create control file
mkdir -p $deb_dir/DEBIAN

cat > $deb_dir/DEBIAN/control << EOF
Package: emacs-dev
Version: $emacs_pkg_version
Architecture: $arch
Maintainer: www.gnu.org/software/emacs/
Description: GNU Emacs
Depends: libjansson4,libncurses5,libgccjit0,libtree-sitter0,libwebkit2gtk-4.0-37${render_deps}
EOF

dpkg-deb --build -z9 --root-owner-group $deb_dir
