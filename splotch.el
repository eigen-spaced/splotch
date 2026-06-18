;;; splotch.el --- Control the Spotify app  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; Keywords: multimedia, music, spotify, splotch
;; Package: splotch
;; Package-Requires: ((emacs "27.1") (simple-httpd "1.5.1") (request "0.3") (oauth2 "0.18"))
;; Version: 1.0.0
;; Homepage: https://github.com/eigen-spaced/splotch

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This mode requires at least GNU Emacs 27.1

;; Before using this mode, first go the Spotify Web API console
;; <https://developer.spotify.com/my-applications> and create a new application,
;; adding <http://127.0.0.1:8080/splotch_api_callback> as the redirect URI (or
;; whichever port you have specified via customize).

;; After requiring `splotch', make sure to define the client id and client
;; secrets, along with some other important settings.

;;; Code:

(when (version< emacs-version "27.1")
  (error "Splotch requires at least GNU Emacs 27.1"))

(require 'subr-x)
(require 'json)
(require 'tabulated-list)
(require 'easymenu)

(require 'splotch-api)
(require 'splotch-track)
(require 'splotch-playlist)
(require 'splotch-device-select)
(require 'splotch-controller)
(require 'splotch-remote)
(require 'splotch-lyrics)

(splotch-when-darwin    (require 'splotch-apple))
(splotch-when-gnu-linux (require 'splotch-dbus))

(require 'splotch-connect)

(defgroup splotch nil
  "Splotch Spotify client."
  :version "0.0.1"
  :group 'multimedia)

;;;###autoload
(defun splotch-track-search (query)
  "Search for tracks that match the given QUERY string."
  (interactive "sSpotify Search (Tracks): ")
  (let ((buffer (get-buffer-create (format "*Track Search: %s*" query))))
    (with-current-buffer buffer
      (splotch-track-search-mode)
      (splotch-track-search-update query 1))))

;;;###autoload
(defun splotch-playlist-search (query)
  "Search for playlists that match the given QUERY string."
  (interactive "sSpotify Search (Playlists): ")
  (let ((buffer (get-buffer-create (format "*Playlist Search: %s*" query))))
    (with-current-buffer buffer
      (splotch-playlist-search-mode)
      (splotch-playlist-search-update query 1))))

;;;###autoload
(defun splotch-recently-played ()
  "Display recently played tracks."
  (interactive)
  (let ((buffer (get-buffer-create "*Recently Played*")))
    (with-current-buffer buffer
      (splotch-track-search-mode)
      (splotch-track-recently-played-tracks-update 1))))

;;;###autoload
(defun splotch-my-library ()
  "Display the songs saved in the current user's Liked Songs."
  (interactive)
  (let ((buffer (get-buffer-create "*Liked Songs*")))
    (with-current-buffer buffer
      (splotch-track-search-mode)
      (splotch-track-my-library-update 1))))

;;;###autoload
(defun splotch-my-playlists ()
  "Display the current user's playlists."
  (interactive)
  (splotch-api-current-user
   (lambda (user)
     (splotch-user-playlists (splotch-api-get-item-id user)))))

;;;###autoload
(defun splotch-user-playlists (user-id)
  "Display the public playlists of the given user with USER-ID."
  (interactive "sSpotify User ID: ")
  (let ((buffer (get-buffer-create (format "*Playlists: %s*" user-id))))
    (with-current-buffer buffer
      (splotch-playlist-search-mode)
      (splotch-playlist-user-playlists-update user-id 1))))

;;;###autoload
(defun splotch-create-playlist (name public)
  "Create an empty playlist owned by the current user.
Prompt for the NAME and whether it should be made PUBLIC."
  (interactive
   (list (read-string "Playlist name: ")
         (y-or-n-p "Make the playlist public? ")))
  (if (string= name "")
      (message "Playlist name not provided; aborting")
    (splotch-api-current-user
     (lambda (user)
       (splotch-api-playlist-create
        (splotch-api-get-item-id user)
        name
        public
        (lambda (new-playlist)
          (if new-playlist
              (message "Playlist '%s' created" (splotch-api-get-item-name new-playlist))
            (message "Error creating the playlist"))))))))

(defvar splotch-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") '("splotch/play-pause"     . splotch-controller-toggle-play))
    (define-key map (kbd "b")   '("splotch/previous-track" . splotch-controller-previous-track))
    (define-key map (kbd "n")   '("splotch/next-track"     . splotch-controller-next-track))
    (define-key map (kbd "d")   '("splotch/select-device"  . splotch-select-device))
    (define-key map (kbd "r")   '("splotch/toggle-repeat"  . splotch-controller-toggle-repeat))
    (define-key map (kbd "s")   '("splotch/toggle-shuffle" . splotch-controller-toggle-shuffle))
    (define-key map (kbd "p")   '("splotch/playlists"      . splotch-playlists))
    (define-key map (kbd "t")   '("splotch/tracks"         . splotch-tracks))
    (define-key map (kbd "l")   '("splotch/lyrics"         . splotch-lyrics-popup))
    (define-key map (kbd "v")   '("splotch/volume"         . splotch-volume))
    map)
  "Keymap for Spotify commands after \\='splotch-keymap-prefix\\='.")

;;;###autoload
(defalias 'splotch-playlists
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "m") '("splotch/my-playlists"     . splotch-my-playlists))
    (define-key map (kbd "u") '("splotch/user-playlists"   . splotch-user-playlists))
    (define-key map (kbd "s") '("splotch/search-playlists" . splotch-playlist-search))
    (define-key map (kbd "c") '("splotch/create-playlists" . splotch-create-playlist))
    map)
  "Playlist-related bindings.")

;;;###autoload
(defalias 'splotch-tracks
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s") '("splotch/search-tracks"       . splotch-track-search))
    (define-key map (kbd "r") '("splotch/recently-played"     . splotch-recently-played))
    (define-key map (kbd "l") '("splotch/save-to-library"     . splotch-save-playing-track-to-library))
    (define-key map (kbd "k") '("splotch/remove-from-library" . splotch-remove-playing-track-from-library))
    (define-key map (kbd "a") '("splotch/add-to-playlist"     . splotch-add-playing-track-to-playlist))
    map)
  "Track-related bindings.")

;;;###autoload
(defalias 'splotch-volume
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "m")   '("splotch/mute-unmute" . splotch-controller-volume-mute-unmute))
    (define-key map (kbd "u")   '("splotch/volume-up"   . splotch-controller-volume-up))
    (define-key map (kbd "d")   '("splotch/volume-down" . splotch-controller-volume-down))
    map)
  "Spotify player volume bindings.")

(easy-menu-add-item nil '("Tools")
                    '("Splotch"
                      ["Play/Pause"     splotch-controller-toggle-play]
                      ["Previous Track" splotch-controller-previous-track]
                      ["Next Track"     splotch-controller-next-track]
                      ["Lyrics"         splotch-lyrics-popup]
                      "--"
                      ["Select Playing Device" splotch-select-device]
                      ["Mute/Unmute"           splotch-controller-volume-mute-unmute]
                      "--"
                      ["Shuffle" splotch-controller-toggle-shuffle]
                      ["Repeat"  splotch-controller-toggle-repeat]
                      "--"
                      ["Search Tracks..."    splotch-track-search]
                      ["My Playlists"        splotch-my-playlists]
                      ["User Playlists..."   splotch-user-playlists]
                      ["Search Playlists..." splotch-playlist-search]
                      ["Create Playlist..."  splotch-create-playlist]
                      "--"
                      ["Splotch Remote Mode" global-splotch-remote-mode :style toggle :selected global-splotch-remote-mode]))

(defun splotch-remote-popup-menu ()
  "Popup menu when in splotch-remote-mode."
  (interactive)
  (popup-menu
   '("Splotch"
     ["Play/Pause" splotch-controller-toggle-play]
     ["Previous Track" splotch-controller-previous-track]
     ["Next Track" splotch-controller-next-track]
     ["Lyrics" splotch-lyrics-popup]
     "--"
     ["Select Device" splotch-select-device]
     ["Mute/Unmute" splotch-controller-volume-mute-unmute]
     "--"
     ["Shuffle" splotch-controller-toggle-shuffle]
     ["Repeat"  splotch-controller-toggle-repeat]
     "--"
     ["Search Tracks..."    splotch-track-search]
     ["My Playlists"        splotch-my-playlists]
     ["User Playlists..."   splotch-user-playlists]
     ["Search Playlists..." splotch-playlist-search]
     ["Create Playlist..."  splotch-create-playlist])))

(provide 'splotch)
;;; splotch.el ends here
