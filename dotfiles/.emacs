(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("9cd784dfeea58d9d852d52be9126c1fba2b890ed368245624dec1df165a4f6fd" default))
 '(inhibit-startup-screen t)
 '(tool-bar-mode nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
(add-to-list 'custom-theme-load-path (expand-file-name "~/.emacs.d/themes/"))
;;(load-theme 'nord t)
(if (display-graphic-p)
    (progn
      (set-face-attribute 'mode-line nil
                          :background "#353644"
                          :foreground "white"
                          :box '(:line-width 8 :color "#353644")
                          :overline nil
                          :underline nil)
      (set-face-attribute 'mode-line-inactive nil
                          :background "#565063"
                          :foreground "white"
                          :box '(:line-width 8 :color "#565063")
                          :overline nil
                          :underline nil))
  ;; Terminal: disable inverse-video and skip :box
  (set-face-attribute 'mode-line nil
                      :background "#353644"
                      :foreground "white"
                      :inverse-video nil
                      :box nil
                      :overline nil
                      :underline nil)
  (set-face-attribute 'mode-line-inactive nil
                      :background "#565063"
                      :foreground "white"
                      :inverse-video nil
                      :box nil
                      :overline nil
                      :underline nil))
;; Disable GUI chrome
(tool-bar-mode -1)
(menu-bar-mode -1)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(menu-bar-lines . 0) default-frame-alist)

;; 1. Define the function to extract the Git/Hg branch name safely
(defun vc-branch ()
  (if (and (boundp 'vc-mode) vc-mode buffer-file-name)
      (let ((backend (vc-backend buffer-file-name)))
        (propertize (concat "  " (substring vc-mode (+ (if (eq backend 'Hg) 2 3) 2)) " ")
                    'face 'font-lock-string-face))
    ""))

;; 2. Reconstruct the modeline structure to use our changes

;; Remove dash padding from percentage (the (-3 "%p") default).
(setq-default mode-line-percent-position '("%p"))

;; Replace front/end dashes with plain spaces.
(setq-default mode-line-front-space " ")
(setq-default mode-line-end-spaces " ")

(setq-default mode-line-format
  '(
    ;; Left side info
    "%e"
    mode-line-front-space
    (:eval (if (buffer-modified-p)
               (propertize " ● " 'face 'error)
             ""))
    mode-line-remote
    (:propertize mode-line-buffer-identification face font-lock-type-face)
    "   "
    mode-line-position

    ;; Git branch (colored)
    (:eval (vc-branch))

    ;; Right-align the major mode name
    (:eval (let ((rhs-width (+ 3 (string-width (format-mode-line mode-name)))))
             (propertize " " 'display
                         `((space :align-to (- (+ right right-fringe right-margin)
                                               ,rhs-width))))))
    mode-name
    mode-line-end-spaces
    ))
