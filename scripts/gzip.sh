function action3_gzip () {
    gzip_build_dir="$emacs_build_build_dir/gzip"
    gzip_zip_file="$emacs_build_zip_dir/gzip-${architecture}.zip"

    if test ! -f "${gzip_zip_file}"; then
        (mkdir -p "$gzip_build_dir/usr/bin" \
             && echo '%~dp0\gzip.exe -d %*' > "${gzip_build_dir}/usr/bin/gunzip.cmd" \
             && cp /usr/bin/gzip.exe "${gzip_build_dir}/usr/bin/gzip.exe" \
             && ensure_packages gzip \
             && msys2_extra_package "msys2-runtime" "/" "" "$gzip_zip_file" \
             && cd "${gzip_build_dir}" \
             && zip -9r "$gzip_zip_file" "usr") || return -1
    fi
    emacs_extensions="$gzip_zip_file $emacs_extensions"
}
