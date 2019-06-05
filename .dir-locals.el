;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")

((python-mode . ((eval progn
                       (setq python-shell-virtualenv-root
                             (concat
                              (locate-dominating-file default-directory dir-locals-file)
                              "/.venv")))
                 (encoding . utf-8)))
 )
