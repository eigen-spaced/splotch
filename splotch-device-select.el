;;; splotch-device-select.el --- Splotch device selection major mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2019-2025 Jason Dufair, Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library implements methods, UI, and a minor mode to use the "connect"
;; RESTful APIs to manage and query Spotify clients on the network.

;;; Code:

(require 'splotch-api)
(require 'splotch-controller)

(defcustom splotch-selected-device-id ""
  "The id of the device selected for transport."
  :group 'splotch
  :type 'string)

(defvar splotch-device-select-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "g") 'splotch-device-select-update)
    (define-key map (kbd "u") 'splotch-controller-volume-up)
    (define-key map (kbd "d") 'splotch-controller-volume-down)
    (define-key map (kbd "m") 'splotch-controller-volume-mute-unmute)
    (define-key map (kbd "r") 'splotch-controller-toggle-repeat)
    (define-key map (kbd "s") 'splotch-controller-toggle-shuffle)
    map)
  "Local keymap for `splotch-device-select-mode' buffers.")

(define-derived-mode splotch-device-select-mode tabulated-list-mode "Device-Select"
  "Major mode for selecting a Spotify Connect device for transport.")

(defun splotch-device-select-update ()
  "Fetches the list of devices using the device list endpoint."
  (interactive)
  (let ((buffer (current-buffer)))
    (splotch-api-device-list
     (lambda (json)
       (if-let ((devices (gethash "devices" json))
                (line (string-to-number (format-mode-line "%l"))))
           (progn
             (pop-to-buffer buffer)
             (splotch-devices-print devices)
             (goto-char (point-min))
             (forward-line (1- line))
             (message "Device list updated."))
         (message "No devices are available."))))))

(defun splotch-device-select-active ()
  "Set the selected device to the active device per the API."
  (splotch-api-device-list
   (lambda (json)
     (when-let ((devices (gethash "devices" json)))
       (while (let* ((device (car devices))
                     (is-active (splotch-device-get-device-is-active device)))
                (progn
                  (when (and device is-active)
                    (progn
                      (setq splotch-selected-device-id (splotch-device-get-device-id device))
                      (splotch-controller-player-status)))
                  (setq devices (cdr devices))
                  (and device (not is-active)))))))))

(defun splotch-devices-print (devices)
  "Append the given DEVICES to the devices view."
  (let (entries)
    (dolist (device devices)
      (let ((name (splotch-device-get-device-name device))
            (is-active (splotch-device-get-device-is-active device))
            (is-restricted (splotch-device-get-device-is-restricted device))
            (volume (splotch-device-get-device-volume device))
            (device-id (splotch-device-get-device-id device)))
        (unless is-restricted
          (push
           (list device
                 (vector
                  (cons name
                        (list 'face 'link
                              'follow-link t
                              'action `(lambda (_)
                                         (splotch-api-transfer-player
                                          ,device-id
                                          (lambda (json)
                                            (setq splotch-selected-device-id ,device-id)
                                            (message "Device '%s' selected" ,name))))
                              'help-echo (format "Select '%s' for transport" name)))
                  (if is-active "X" "")
                  (if is-active (number-to-string volume) "")))
           entries))))
    (setq-local tabulated-list-entries nil)
    (setq-local tabulated-list-entries (append tabulated-list-entries (nreverse entries)))
    (splotch-device-set-list-format)
    (tabulated-list-init-header)
    (tabulated-list-print t)))

(defun splotch-device-set-list-format ()
  "Configures the column data for the device view."
  (setq tabulated-list-format
        (vector `("Device" ,(- (window-width) 24) nil)
                '("Active" 12 nil)
                '("Volume" 8 nil :right-align nil))))

(defun splotch-device-get-device-name (device)
  "Return the name from the given DEVICE hash."
  (gethash "name" device))

(defun splotch-device-get-device-is-active (device)
  "Return whether the DEVICE is currently playing content."
  (eq (and device (gethash "is_active" device)) t))

(defun splotch-device-get-device-volume (device)
  "Return the volume of the DEVICE."
  (gethash "volume_percent" device))

(defun splotch-device-get-device-is-restricted (device)
  "Return whether the DEVICE can receive commands."
  (eq (gethash "is_restricted" device) t))

(defun splotch-device-get-device-id (device)
  "Return the unique id of DEVICE."
  (gethash "id" device))

(provide 'splotch-device-select)
;;; splotch-device-select.el ends here
