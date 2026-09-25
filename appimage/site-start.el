;;; site-start.el --- AppImage GCC JIT paths -*- lexical-binding: t; -*-

(let ((appdir (getenv "APPDIR")))
  (when appdir
    (setq native-comp-driver-options
          (list (concat "-B" appdir "/usr/libexec/emacs-jit/bin/")
                (concat "-B" appdir "/usr/lib/gcc/x86_64-linux-gnu/14/")))))
