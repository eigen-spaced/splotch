;;; splotch-connect.el --- Control remote and local Spotify instances  -*- lexical-binding: t; -*-

;; Copyright (C) 2019-2025 Jason Dufair, Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library uses the "connect" APIs to control transport functions of
;; remote and local instances of Spotify clients.  It implements a set of
;; multimethod-like functions that are dispatched in splotch-controller.el.

;; splotch-connect.el --- Splotch transport for the Spotify Connect API

;;; Code:

(require 'splotch-api)
(require 'splotch-controller)

(defun splotch-connect-player-status ()
  "Get the player status of the currently playing device, if any.
Returns a JSON string in the format:
{
  \"artist\": \"Aesop Rock\",
  \"duration\": 265333,
  \"track_number\": 9,
  \"name\":  \"Shrunk\",
  \"player_state\": \"playing\",
  \"player_shuffling\": \"t\",
  \"player_repeating\": \"context\"
}"
  (condition-case err
      (splotch-api-get-player-status
       (lambda (status)
         (condition-case parse-err
             (if-let* ((status status)
                       (track (gethash "item" status))
                       (json (concat
                              "{"
                              (format "\"artist\":\"%s\","
                                      (gethash "name" (car (gethash "artists" track))))
                              (format "\"duration\": %d,"
                                      (gethash "duration_ms" track))
                              (format "\"track_number\":%d,"
                                      (gethash "track_number" track))
                              (format "\"name\":\"%s\","
                                      (gethash "name" track))
                              (format "\"player_state\":\"%s\","
                                      (if (eq (gethash "is_playing" status) :false) "paused" "playing"))
                              (format "\"player_shuffling\":%s,"
                                      (if (not (eq (gethash "shuffle_state" status) :false))"true" "false"))
                              (format "\"player_repeating\":%s"
                                      (if (string= (gethash "repeat_state" status) "off") "false" "true"))
                              "}")))
                 (splotch-controller-update-metadata json)
               (splotch-controller-update-metadata nil))
           (error
            ;; Keep existing status on parse errors to avoid clearing modeline
            nil))))
    (error
     ;; Silently ignore API errors to prevent timer from stopping
     nil)))

;;;###autoload
(defun splotch-select-device ()
  "Allow for the selection of a device via Spotify Connect for transport functions."
  (interactive)
  (splotch-api-current-user
   (lambda (user)
     (if (not (string= (gethash "product" user) "premium"))
         (message "This feature requires a Spotify premium subscription.")
       (let ((buffer (get-buffer-create "*Devices*")))
         (with-current-buffer buffer
           (splotch-device-select-mode)
           (splotch-device-select-update)))))))

(defmacro splotch-connect-when-device-active (body)
  "Evaluate BODY when there is an active device, otherwise show an error message."
  `(splotch-api-device-list
    (lambda (json)
      (if-let ((json json)
               (devices (gethash "devices" json))
               (active (> (length (seq-filter (lambda (dev) (eq (gethash "is_active" dev) t)) devices)) 0)))
          (progn ,body)
        (when (y-or-n-p "No active device. Would you like to select one?")
          (splotch-select-device))))))

(defun splotch-connect-player-play-track (uri &optional context)
  "Play a track URI via Spotify Connect in an optional CONTEXT."
  (splotch-connect-when-device-active
   (splotch-api-play nil uri context)))

(defun splotch-connect-player-pause ()
  "Pause the currently playing track."
  (splotch-connect-when-device-active
   (splotch-api-pause)))

(defun splotch-connect-player-toggle-play ()
  "Toggle playing status of current track."
  (splotch-connect-when-device-active
   (splotch-api-get-player-status
    (lambda (status)
      (if status
          (if (not (eq (gethash "is_playing" status) :false))
              (splotch-api-pause)
            (splotch-api-play)))))))

(defun splotch-connect-player-next-track ()
  "Skip to the next track."
  (splotch-connect-when-device-active
   (splotch-api-next)))

(defun splotch-connect-player-previous-track ()
  "Skip to the previous track."
  (splotch-connect-when-device-active
   (splotch-api-previous)))

(defun splotch-connect-volume-up ()
  "Turn up the volume on the actively playing device."
  (splotch-connect-when-device-active
   (splotch-api-get-player-status
    (lambda (status)
      (let ((new-volume (min (+ (splotch-connect-get-volume status) 10) 100)))
        (splotch-api-set-volume
         (splotch-connect-get-device-id status)
         new-volume
         (lambda (_)
           (message "Volume increased to %d%%" new-volume))))))))

(defun splotch-connect-volume-down ()
  "Turn down the volume (for what?) on the actively playing device."
  (splotch-connect-when-device-active
   (splotch-api-get-player-status
    (lambda (status)
      (let ((new-volume (max (- (splotch-connect-get-volume status) 10) 0)))
        (splotch-api-set-volume
         (splotch-connect-get-device-id status)
         new-volume
         (lambda (_)
           (message "Volume decreased to %d%%" new-volume))))))))

(defun splotch-connect-volume-mute-unmute ()
  "Mute/unmute the actively playing device by setting the volume to 0."
  (splotch-connect-when-device-active
   (splotch-api-get-player-status
    (lambda (status)
      (let ((volume (splotch-connect-get-volume status)))
        (if (eq volume 0)
            (splotch-api-set-volume (splotch-connect-get-device-id status) 100
                                   (lambda (_) (message "Volume unmuted")))
          (splotch-api-set-volume (splotch-connect-get-device-id status) 0
                                 (lambda (_) (message "Volume muted")))))))))

(defun splotch-connect-toggle-repeat ()
  "Toggle repeat for the current track."
  (splotch-connect-when-device-active
   (splotch-api-get-player-status
    (lambda (status)
      (let ((is-repeating (splotch-connect--is-repeating status)))
        (splotch-api-repeat (if is-repeating "off" "context")
                           (lambda (_)
                             (if is-repeating
                                 (message "Repeat turned off")
                               (message "Repeat turned on")))))))))

(defun splotch-connect-toggle-shuffle ()
  "Toggle shuffle for the current track."
  (splotch-connect-when-device-active
   (splotch-api-get-player-status
    (lambda (status)
      (let ((is-shuffling (splotch-connect--is-shuffling status)))
        (splotch-api-shuffle (if is-shuffling "false" "true")
                            (lambda (_)
                              (if is-shuffling
                                  (message "Shuffling turned off")
                                (message "Shuffling turned on")))))))))

(defun splotch-connect-get-device-id (player-status)
  "Get the id if from PLAYER-STATUS of the currently playing device, if any."
  (when player-status
    (gethash "id" (gethash "device" player-status))))

(defun splotch-connect-get-volume (player-status)
  "Get the volume from PLAYER-STATUS of the currently playing device, if any."
  (when player-status
    (gethash "volume_percent" (gethash "device" player-status))))

(defun splotch-connect--is-shuffling (player-status)
  "Business logic for shuffling state of PLAYER-STATUS."
  (and player-status
       (not (eq (gethash "shuffle_state" player-status) :false))))

(defun splotch-connect--is-repeating (player-status)
  "Business logic for repeat state of PLAYER-STATUS."
  (and player-status
       (string= (gethash "repeat_state" player-status) "context")))


(provide 'splotch-connect)

;;; splotch-connect.el ends here
