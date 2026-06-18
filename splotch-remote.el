;; splotch-remote.el --- Splotch remote minor mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library implements a minor mode that allows for interacting with
;; Spotify and displaying transport status.  This also includes a global
;; minor mode definition.

;;; Code:

(require 'splotch-controller)
(require 'splotch-device-select)

(defcustom splotch-keymap-prefix nil
  "Splotch remote keymap prefix."
  :group 'splotch
  :type 'string)

(defcustom splotch-status-location 'modeline
  "Specify where to show the player status: one of \\='(modeline title-bar nil)."
  :type '(choice (const :tag "Modeline" modeline)
          (const :tag "Title Bar" title-bar)
          (const :tag "Do not show" nil))
  :group 'splotch)

(defcustom splotch-title-bar-separator "    "
  "String used to separate player status from the remaining text on the title bar."
  :type 'string
  :group 'splotch)

(defun splotch-remote-add-frame-title-status (status title-section)
  "Return the TITLE-SECTION or part thereof with the player STATUS appended."
  (if (stringp title-section)
      (cons title-section (list status))
    (append title-section (list status))))

(defun splotch-remote-set-frame-title (status)
  "Parse and set the frame title, appending STATUS to all frame scenarios."
  (splotch-remote-remove-status-from-frame-title status)
  (setq frame-title-format
        (if (and (listp frame-title-format) (eq (car frame-title-format) 'multiple-frames))
            (let ((multiple-frame-format (car (nthcdr 1 frame-title-format)))
                  (single-frame-format (car (nthcdr 2 frame-title-format))))
              (list 'multiple-frames
                    (splotch-remote-add-frame-title-status status multiple-frame-format)
                    (splotch-remote-add-frame-title-status status single-frame-format)))
          (splotch-remote-add-frame-title-status status frame-title-format))))

(defun splotch-remote-remove-status-from-frame-title (status)
  "Parse the frame title and remove the player STATUS."
  (setq frame-title-format
        (if (not (listp frame-title-format))
            frame-title-format
          (if (member status frame-title-format)
              (remove status frame-title-format)
            (mapcar (lambda (section)
                      (if (and (listp section) (member status section))
                          (remove status section)
                        section))
                    frame-title-format)))))

(defvar splotch-mode-map
  (let ((map (make-sparse-keymap)))
    (when splotch-keymap-prefix
      (define-key map splotch-keymap-prefix 'splotch-command-map))
    map)
  "Keymap for Splotch remote mode.")

;;;###autoload
(define-minor-mode global-splotch-remote-mode
  "Toggles Splotch Remote mode.
A positive prefix argument enables the mode, any other prefix
argument disables it. From Lisp, argument omitted or nil enables
the mode, `toggle' toggles the state.

When Splotch Remote mode is enabled, it's possible to toggle
the repeating and shuffling status of the running Spotify process.
See commands \\[splotch-toggle-repeating] and
\\[splotch-toggle-shuffling]."
  :group 'splotch
  :init-value nil
  :global t
  :keymap splotch-mode-map
  (let ((s `(,splotch-title-bar-separator (:eval (splotch-remote-player-status-text)))))
    (if global-splotch-remote-mode
        (progn
          (splotch-controller-start-player-status-timer)
          (cond ((or (eq splotch-status-location 'modeline) (not (display-graphic-p)))
                 (unless (member s global-mode-string)
                   (push s global-mode-string)))
                ((eq splotch-status-location 'title-bar)
                 (splotch-remote-set-frame-title s)))
          (when (eq splotch-transport 'connect)
            (splotch-device-select-active)))
      (progn
        (splotch-controller-stop-player-status-timer)
        (cond ((or (eq splotch-status-location 'modeline) (not (display-graphic-p)))
               (when (member s global-mode-string)
                 (setq global-mode-string (remove s global-mode-string))))
              ((eq splotch-status-location 'title-bar)
               (splotch-remote-remove-status-from-frame-title s)))))))

(defvar splotch-remote-player-status-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<mode-line> <mouse-1>") 'splotch-remote-popup-menu)
    map)
  "Keymap for Splotch mode-line status.")

(defun splotch-remote-update-player-status (str)
  "Set the given STR to the player status, prefixed with the mode identifier."
  (unless (string= str splotch-controller-player-status)
    (setq splotch-controller-player-status str)
    (force-mode-line-update t)))

(defun splotch-remote-player-status-text ()
  "Return the propertized text to be displayed as the lighter."
  (propertize splotch-controller-player-status
              'keymap splotch-remote-player-status-map
              'help-echo "mouse-1: Show splotch.el menu"
              'mouse-face 'mode-line-highlight))

(provide 'splotch-remote)
;;; splotch-remote.el ends here
