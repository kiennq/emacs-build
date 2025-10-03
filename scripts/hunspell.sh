function action3_hunspell ()
{
    local hunspell_zip_file="$emacs_build_zip_dir/hunspell-${architecture}.zip"
    if test -f "$hunspell_zip_file"; then
        echo File $hunspell_zip_file already exists.
        emacs_extensions="$hunspell_zip_file $emacs_extensions" \
        && return 0
    else
        local packages="${mingw_prefix}-hunspell ${mingw_prefix}-hunspell-en"
        ensure_packages "$packages" \
            && msys2_extra_package "$packages" "$mingw_dir" "" "$hunspell_zip_file" \
            && emacs_extensions="$hunspell_zip_file $emacs_extensions" \
            && return 0
        return -1
    fi
}
