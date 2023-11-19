set msys2_dir=c:\msys64
set emacs_branch=emacs-29
call .\emacs-build.cmd --clone --repo https://git.savannah.gnu.org/git/emacs.git --branch %emacs_branch% --depth 1
call .\emacs-build.cmd --branch %emacs_branch% --nativecomp --slim --without-pop --without-imagemagick --without-compress-install --without-dbus --with-gnutls --with-json --with-tree-sitter --without-gconf --with-rsvg --without-gsettings --with-mailutils --with-modules  --with-xml2 --with-wide-int --build
call .\emacs-build.cmd --branch %emacs_branch% --nativecomp --slim --without-pop --without-imagemagick --without-compress-install --without-dbus --with-gnutls --with-json --with-tree-sitter --without-gconf --with-rsvg --without-gsettings --with-mailutils --with-modules  --with-xml2 --with-wide-int --pack-all