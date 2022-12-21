#!/bin/bash
# Copyright 2020 Juan Jose Garcia-Ripoll
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
########################################
#
# EMACS-BUILD
#
# Standalone script to build Emacs from a running copy of Mingw64. It immitates
# the steps that Emacs developers can take to build the standard distributions.
# See write_help below for all options.
#

. scripts/tools.sh
. scripts/pdf-tools.sh
. scripts/aspell.sh
. scripts/hunspell.sh
. scripts/msys2_extra.sh
. scripts/gnutls.sh

function write_help () {
    echo "Emacs-build tool version $emacs_build_version, (c) 2020 Juan Jose Garcia-Ripoll"
    cat "$emacs_build_root/scripts/help.txt"
    echo
    write_features
}

function write_features () {
    local inactive=""
    for f in $all_features; do
        if [[ ! " $features " =~ .*$f ]]; then
            inactive="$f $inactive"
        fi
    done

    echo "Compressed installation: $emacs_compress_files"
    echo "Strip executables: $emacs_strip_executables"
    echo "Emacs features:"
    for f in $features; do echo "  --with-$f"; done
    for f in $inactive; do echo " --without $f"; done
}

function write_version_number ()
{
    echo $emacs_build_version
    exit 0
}

function check_mingw_architecture ()
{
    case "$MSYSTEM" in
        MINGW32) architecture=i686
                 mingw_prefix="mingw-w64-i686"
                 mingw_dir="$MINGW_PREFIX/"
                 build_type="i686-w64-mingw32"
                 ;;
        MINGW64) architecture=x86_64
                 mingw_prefix="mingw-w64-x86_64"
                 mingw_dir="$MINGW_PREFIX/"
                 build_type="x86_64-w64-mingw32"
                 ;;
        MSYSTEM) echo This tool cannot be ran from an MSYS shell.
                 echo Please open a Mingw64 or Mingw32 terminal.
                 echo
                 exit -1
                 ;;
        *)       echo This tool must be run from a Mingw64/32 system
                 echo
                 exit -1
    esac
}

function ensure_mingw_build_software ()
{
    local build_packages="zip unzip base-devel ${mingw_prefix}-toolchain"
    pacman -S --noconfirm --needed $build_packages >/dev/null 2>&1
    if test "$?" != 0; then
        echo Unable to install $build_packages
        echo Giving up
        exit -1
    fi
    if [ -z `which git 2>&1` ]; then
        echo Installing Git for MSYS2
        pacman -S --noconfirm --needed git
        if test "$?" != 0; then
            echo Unable to install Git
            echo Giving up
            exit -1
        fi
    fi
}


function emacs_root_packages ()
{
    local feature_selector=`echo $features | sed -e 's, ,|,g'`
    feature_list | grep -E "$feature_selector" | cut -d ' ' -f 2- | sed -e "s,mingw-,${mingw_prefix}-,g"
}

function emacs_dependencies ()
{
    # Print the list of all mingw/msys packages required for running emacs with
    # the selected features. Cache the result value.
    #
    if test -z "$emacs_dependencies"; then
        errcho Inspecting required packages for build features
        errcho   $features
        local packages=`emacs_root_packages`
        # emacs_dependencies=`full_dependency_list "$packages" "${mingw_prefix}-glib2" "Emacs"`
        emacs_dependencies=`full_dependency_list "$packages" "" "Emacs"`
        errcho Total packages required:
        for p in $emacs_dependencies; do
            errcho "  $p"
        done
    fi
    echo $emacs_dependencies
}

function emacs_configure_build_dir ()
{
    cd "$emacs_build_dir"
    options="--disable-build-details --without-dbus"
    if test "$emacs_compress_files" = "no"; then
        options="$options --without-compress-install"
    else
        options="$options --with-compress-install"
    fi

    if test "$emacs_slim_build" = "yes"; then
        options="$options --with-small-ja-dic"
    fi

    for f in $all_features; do
        if echo $features | grep $f > /dev/null; then
            options="--with-$f $options"
        else
            options="--without-$f $options"
        fi
    done
    echo Configuring Emacs with options
    echo   "$emacs_source_dir/configure" "--prefix=$emacs_install_dir" CFLAGS="$CFLAGS" $options
    if "$emacs_source_dir/configure" "--prefix=$emacs_install_dir" CFLAGS="$CFLAGS" $options; then
        echo Emacs configured
    else
        echo Configuration failed
        return -1
    fi
}

function action0_clean ()
{
    rm -rf "$emacs_build_build_dir" "$emacs_build_install_dir"
}

function action0_clean_rest ()
{
    rm -rf "$emacs_build_git_dir" "$emacs_build_zip_dir" msys2-upgraded.log
    exit 0
}

function action0_clone ()
{
    clone_repo "$emacs_branch" "$emacs_repo" "$emacs_source_dir" "$emacs_branch_name" "$emacs_depth"
    if test "$emacs_apply_patches" = "yes"; then
        apply_patches "$emacs_source_dir" || true
    fi

    if test $GITHUB_ENV; then
        echo "EMACS_COMMIT=`git_version $emacs_source_dir`" >> $GITHUB_ENV
        echo "EMACS_MAJOR_VER=`cat $emacs_source_dir/configure.ac | grep -Po 'AC_INIT\(.*\[\K\d+'`" >> $GITHUB_ENV
    fi
}

function action1_ensure_packages ()
{
    # Collect the list of packages required for running Emacs, and ensure they
    # have been installed.
    #
    ensure_packages `emacs_root_packages`
}

function action2_build ()
{
    echo start building
    rm -f "$emacs_install_dir/bin/emacs.exe"
    if prepare_source_dir $emacs_source_dir \
            && prepare_build_dir $emacs_build_dir && emacs_configure_build_dir; then
        echo Building Emacs in directory $emacs_build_dir
        make -j $emacs_build_threads -C $emacs_build_dir && return 0
    fi
    echo Configuration and build process failed
    return -1
}

function action2_install ()
{
    if test -f "$emacs_install_dir/bin/emacs.exe"; then
        echo $emacs_install_dir/bin/emacs.exe exists
        echo refusing to reinstall
    else
        rm -rf "$emacs_install_dir"
        mkdir -p "$emacs_install_dir/bin"
        if test "$emacs_compress_files" = "yes"; then
            # If we compress files we need to install gzip no matter what
            # (even in pack-emacs)
            (ensure_packages gzip \
                 && cp_bindeps_to "$emacs_install_dir/bin" gzip.exe) \
                || return -1
        fi
        echo Installing Emacs into directory $emacs_install_dir
        # HACK!!! Somehow libgmp is not installed as part of the
        # standalone Emacs build process. This is weird, but means
        # we have to copy it by hand.
        make -j $emacs_build_threads -C $emacs_build_dir install \
            && cp "${mingw_dir}bin/libgmp"*.dll "$emacs_install_dir/bin/" \
            && rm -f "$emacs_install_dir/bin/emacs-"*.exe \
            && emacs_build_strip_exes "$emacs_install_dir" \
            && cp "$emacs_build_root/scripts/site-start.el" "$emacs_install_dir/share/emacs/site-lisp" \
            && mkdir -p "$emacs_install_dir/usr/share/emacs/site-lisp/" \
            && cp "$emacs_install_dir/share/emacs/site-lisp/subdirs.el" \
                  "$emacs_install_dir/usr/share/emacs/site-lisp/subdirs.el"
    fi
}

function emacs_build_strip_exes ()
{
    local dir="$1"
    if [ "$emacs_strip_executables" = "yes" ]; then
        find "$dir" -name '*.exe' -exec strip -g --strip-unneeded '{}' '+'
    fi
}

function action3_package_deps ()
{
    # Collect the list of packages required for running Emacs, gather the files
    # from those packages and compress them into $emacs_depsfile
    #
    package_dependencies "$emacs_depsfile" "`emacs_dependencies`"
}

function action4_package_emacs ()
{
    # Package a prebuilt emacs with and without the required dependencies, ready
    # for distribution.
    #
    if test ! -f $emacs_depsfile; then
        echo Missing dependency file $emacs_depsfile. Run with --deps first.
        return -1
    fi
    rm -f "$emacs_nodepsfile" "$emacs_srcfile"
    mkdir -p `dirname "$emacs_nodepsfile"`
    cd "$emacs_install_dir"
    if zip -9vr "$emacs_nodepsfile" *; then
        echo Built $emacs_nodepsfile; echo
    else
        echo Failed to compress distribution file $emacs_nodepsfile; echo
        return -1
    fi
    cd "$emacs_source_dir"
    if zip -x '.git/*' -9vr "$emacs_srcfile" *; then
        echo Built source package $emacs_srcfile
    else
        echo Failed to compress sources $emacs_srcfile; echo
        return -1
    fi
}

function action5_package_all ()
{
    for zipfile in "$emacs_depsfile" $emacs_extensions; do
        if test ! -f "$zipfile"; then
            echo Missing zip file `basename $zipfile.` Cannot build full distribution.
            echo Please use --deps, --build and all extension options before --pack-all.
            echo
            return -1
        fi
    done
    rm -rf "$emacs_full_install_dir"
    if cp -rfp "$emacs_install_dir" "$emacs_full_install_dir"; then
        rm -f "$emacs_distfile"
        cd "$emacs_full_install_dir"
        for zipfile in "$emacs_depsfile" $emacs_extensions; do
            echo Unzipping $zipfile
            if unzip -ox $zipfile; then
                echo Done!;
            else
                echo Failed to unzip $zipfile
                return -1
            fi
        done
        emacs_build_strip_exes "$emacs_full_install_dir"
        if test "$emacs_compress_files" = "no"; then
            xargs zip -9v "$emacs_distfile" ./*
        else
            # find . -type f | sort | dependency_filter > a.txt
            find . -type f | sort | dependency_filter "$packing_slim_exclusion" \
                | xargs zip -9v "$emacs_distfile"
        fi
    fi
}

function feature_list () {
    cat <<EOF
cairo mingw-cairo
gif mingw-giflib
gnutls mingw-gnutls
harfbuzz mingw-harfbuzz
jpeg mingw-libjpeg-turbo
json mingw-jansson
lcms2 mingw-lcms2
png mingw-libpng
rsvg mingw-librsvg
tiff mingw-libtiff
tree-sitter mingw-tree-sitter
xml2 mingw-libxml2
xpm mingw-xpm-nox
zlib mingw-zlib
EOF
    if test "$emacs_nativecomp" = yes; then
        echo native-compilation mingw-libgccjit
    fi
}

function delete_feature () {
    features=`echo $features | sed -e "s,$1,,"`
}

function add_all_features () {
    features="$all_features"
}

function add_feature () {
    features="$1 $features"
}

function add_actions () {
    actions="$actions $*"
}

function dependency_filter () {
    if test -z "$1"; then
        cat -
    else
        grep -P -v "^(`echo $1 | sed 's,[ \n],|,g'`)" -
    fi
}

check_mingw_architecture

lib_inclusions="
advapi32
gcc\.a
gcc_
kernel32
mingw32
mingwex
moldname
msvcrt
pthread
shell32
user32
"

exe_inclusions="
$build_type-
addpm
as
ctags
ebrowse
emacs
emacsclient
etags
ld
objdump
gzip
"

dependency_slim_exclusions="
$build_type
.*bin/(`echo $exe_inclusions | sed 's,\([^ \n]*\)[ \n]\?,(?!\1),g'`).*\.exe$
.*doc
.*include
.*lib.*/lib(`echo $lib_inclusions | sed 's,\([^ \n]*\)[ \n]\?,(?!\1),g'`).*\.a$
etc
lib/((?!emacs)(?!gcc)(?![^/]*\.(a|o)$))
lib/.*\.exe
.*share/((?!licenses))
usr/lib/cmake
usr/lib/gettext
usr/lib/pkgconfig
usr/lib/terminfo
usr/share/aclocal
usr/share/info
usr/share/man.*
usr/share/terminfo
var
"

packing_slim_exclusion="
.*share/((?!emacs)(?!icons)(?!info)(?!licenses))
.*share/emacs/.*/lisp/leim
.*share/emacs/.*/lisp/play
"

dependency_exclusions=""
all_features=`feature_list | cut -f 1 -d ' '`
features="$all_features"

actions=""
do_clean=""
debug_dependency_list="false"
emacs_compress_files=no
emacs_build_version=0.4
emacs_slim_build=no
emacs_nativecomp=no
emacs_build_threads=$((`nproc`*2))
emacs_apply_patches=yes
# This is needed for pacman to return the right text
export LANG=C
emacs_repo=https://github.com/emacs-mirror/emacs.git
emacs_branch=""
emacs_depth=""
emacs_build_root=`pwd`
emacs_build_git_dir="$emacs_build_root/git"
emacs_build_build_dir="$emacs_build_root/build"
emacs_build_install_dir="$emacs_build_root/pkg"
emacs_build_zip_dir="$emacs_build_root/zips"
emacs_strip_executables="no"

CFLAGS="-Ofast -fno-finite-math-only -fomit-frame-pointer"

while test -n "$*"; do
    case $1 in
        --threads) shift; emacs_build_threads="$1";;
        --repo) shift; emacs_repo="$1";;
        --branch) shift; emacs_branch="$1";;
        --depth) shift; emacs_depth="$1";;
        --no-patches) emacs_apply_patches=no;;
        --with-all) add_all_features;;
        --without-*) delete_feature `echo $1 | sed -e 's,--without-,,'`;;
        --with-*) add_feature `echo $1 | sed -e 's,--with-,,'`;;
        --nativecomp) emacs_nativecomp=yes;;
        --nativecomp-aot) emacs_nativecomp=yes; export NATIVE_FULL_AOT=1;;
        --slim) add_all_features
                delete_feature cairo # We delete features here, so that user can repopulate them
                delete_feature rsvg
                delete_feature tiff
                emacs_slim_build=yes
                emacs_compress_files=yes
                emacs_strip_executables=yes;;
        --strip) emacs_strip_executables=yes;;
        --no-strip) emacs_strip_executables=no;;
        --compress) emacs_compress_files=yes;;
        --no-compress) emacs_compress_files=no;;
        --debug) set -x;;
        --debug-dependencies) debug_dependency_list="true";;

        --clean) add_actions action0_clean;;
        --clean-all) add_actions action0_clean action0_clean_rest;;
        --clone) add_actions action0_clone;;
        --ensure) add_actions action1_ensure_packages;;
        --build) add_actions action1_ensure_packages action2_build;;
        --deps) add_actions action1_ensure_packages action3_package_deps;;
        --pack-emacs) add_actions action2_install action4_package_emacs;;
        --pack-all) add_actions action1_ensure_packages action3_package_deps action2_install action5_package_all;;
        # --pack-all) add_actions action1_ensure_packages action2_install;;

        --pdf-tools) add_actions action2_install action3_pdf_tools;;
        --mu) add_actions action2_install action3_mu;;
        --isync) add_actions action3_isync;;
        --aspell) add_actions action3_aspell;;
        --hunspell) add_actions action3_hunspell;;

        --test-pdf-tools) add_actions test_epdfinfo;;
        --test-mu) add_actions test_mu;;
        --test-isync) add_actions test_isync;;
        --test-aspell) add_actions test_aspell;;


        -?|-h|--help) write_help; exit 0;;
        --features) write_features; exit 0;;
        --version) write_version_number;;
        *) echo Unknown option "$1". Aborting; exit -1;;
    esac
    shift
done
if test "$emacs_nativecomp" = "yes"; then
    all_features=`feature_list | cut -f 1 -d ' '`
    add_feature native-compilation
fi
if test "$emacs_slim_build" = "yes"; then
    dependency_exclusions="$dependency_slim_exclusions"
fi
if test -z "$emacs_branch"; then
    emacs_branch="master"
fi
actions=`unique_list $actions`
if test -z "$actions"; then
    actions="action0_clone action1_ensure_packages action2_build action3_package_deps action5_package_all"
fi
features=`unique_list $features`
ensure_mingw_build_software

emacs_extensions=""
emacs_branch_name=`git_branch_name_to_file_name ${emacs_branch}`
emacs_source_dir="$emacs_build_git_dir/$emacs_branch_name"
emacs_build_dir="$emacs_build_build_dir/$emacs_branch_name-$architecture"
emacs_install_dir="$emacs_build_install_dir/$emacs_branch_name-$architecture"
emacs_full_install_dir="${emacs_install_dir}-full"
emacs_nodepsfile="$emacs_build_root/zips/emacs-${emacs_branch_name}-${architecture}-nodeps.zip"
emacs_depsfile="$emacs_build_root/zips/emacs-${emacs_branch_name}-${architecture}-deps.zip"
emacs_distfile="$emacs_build_root/zips/emacs-${emacs_branch_name}-${architecture}-full.zip"
emacs_srcfile="$emacs_build_root/zips/emacs-${emacs_branch_name}-src.zip"
emacs_dependencies=""
if test "$emacs_branch_name" != "$emacs_branch"; then
    echo Emacs branch ${emacs_branch} renamed to ${emacs_branch_name} to avoid filesystem problems.
fi
for action in $actions; do
    if $action 2>&1 ; then
        echo Action $action succeeded.
    else
        echo Action $action failed.
        echo Aborting builds for branch $emacs_branch and architecture $architecture
        exit -1
    fi
done
