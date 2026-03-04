;; -*- lexical-binding: t; -*-
(let* ((emacs-libexec-path (car (last exec-path)))
       (emacs-libexec-ndx (string-match "libexec" emacs-libexec-path))
       (emacs-root (substring emacs-libexec-path 0 emacs-libexec-ndx))
       (msys2-dir (expand-file-name "usr/bin/" emacs-root))
       (mingw-dir (expand-file-name "bin/" emacs-root)))
  (add-to-list 'exec-path msys2-dir)
  (add-to-list 'exec-path mingw-dir)
  (setenv "PATH" (concat mingw-dir ";" msys2-dir ";" (getenv "PATH")))
  (let ((default-directory (expand-file-name "usr/share/emacs/site-lisp/" emacs-root)))
    (when (file-exists-p default-directory)
      (if (fboundp 'normal-top-level-add-subdirs-to-load-path)
	  (normal-top-level-add-subdirs-to-load-path)))))

;; This is for MSYS2 tools
(setenv "TMPDIR" (getenv "TEMP"))
