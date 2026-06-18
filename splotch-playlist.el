;;; splotch-playlist.el --- Splotch playlist search major mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library implements UI and a major mode for searching and acting on
;; Spotify playlists.

;;; Code:

(require 'splotch-api)
(require 'splotch-controller)
(require 'splotch-track)

(defvar splotch-user-id)
(defvar splotch-current-page)
(defvar splotch-browse-message)
(defvar splotch-selected-playlist)
(defvar splotch-query)

(defvar splotch-playlist-search-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "M-RET") 'splotch-playlist-select)
    (define-key map (kbd "l")     'splotch-playlist-load-more)
    (define-key map (kbd "g")     'splotch-playlist-reload)
    (define-key map (kbd "f")     'splotch-playlist-follow)
    (define-key map (kbd "u")     'splotch-playlist-unfollow)
    map)
  "Local keymap for `splotch-playlist-search-mode' buffers.")

(define-derived-mode splotch-playlist-search-mode tabulated-list-mode "Playlist-Search"
  "Major mode for displaying the playlists returned by a Spotify search.")

(defun splotch-playlist-select ()
  "Plays the playlist under the cursor."
  (interactive)
  (let ((selected-playlist (tabulated-list-get-id)))
    (splotch-controller-play-track nil selected-playlist)))

(defun splotch-playlist-reload ()
  "Reloads the first page of results for the current playlist view."
  (interactive)
  (let ((page 1))
    (cond ((bound-and-true-p splotch-query) (splotch-playlist-search-update splotch-query page))
          (t (splotch-playlist-user-playlists-update splotch-user-id page)))))

(defun splotch-playlist-load-more ()
  "Load the next page of results for the current playlist view."
  (interactive)
  (let ((next-page (1+ splotch-current-page)))
    (cond ((bound-and-true-p splotch-query) (splotch-playlist-search-update splotch-query next-page))
          (t (splotch-playlist-user-playlists-update splotch-user-id next-page)))))

(defun splotch-playlist-follow ()
  "Add the current user as the follower of the playlist under the cursor."
  (interactive)
  (let* ((selected-playlist (tabulated-list-get-id))
         (name (splotch-api-get-item-name selected-playlist)))
    (when (y-or-n-p (format "Follow playlist '%s'? " name))
      (splotch-api-playlist-follow
       selected-playlist
       (lambda (_)
         (message "Followed playlist '%s'" name))))))

(defun splotch-playlist-unfollow ()
  "Remove the current user as the follower of the playlist under the cursor."
  (interactive)
  (let* ((selected-playlist (tabulated-list-get-id))
         (name (splotch-api-get-item-name selected-playlist)))
    (when (y-or-n-p (format "Unfollow playlist '%s'? " name))
      (splotch-api-playlist-unfollow
       selected-playlist
       (lambda (_)
         (message "Unfollowed playlist '%s'" name))))))

(defun splotch-playlist-search-update (query page)
  "Fetch the given PAGE of QUERY results using the search endpoint."
  (let ((buffer (current-buffer)))
    (splotch-api-search
     'playlist
     query
     page
     (lambda (playlists)
       (if-let ((items (splotch-api-get-search-playlist-items playlists)))
           (with-current-buffer buffer
             (setq-local splotch-current-page page)
             (setq-local splotch-query query)
             (pop-to-buffer buffer)
             (splotch-playlist-search-print items page)
             (message "Playlist view updated"))
         (message "No more playlists"))))))

(defun splotch-playlist-user-playlists-update (user-id page)
  "Fetch PAGE of results using the playlist endpoint for USER-ID."
  (let ((buffer (current-buffer)))
    (splotch-api-user-playlists
     user-id
     page
     (lambda (playlists)
       (if-let ((items (splotch-api-get-items playlists)))
           (with-current-buffer buffer
             (setq-local splotch-user-id user-id)
             (setq-local splotch-current-page page)
             (pop-to-buffer buffer)
             (splotch-playlist-search-print items page)
             (message "Playlist view updated"))
         (message "No more playlists"))))))

(defun splotch-playlist-tracks ()
  "Displays the tracks that belongs to the playlist under the cursor."
  (interactive)
  (let* ((selected-playlist (tabulated-list-get-id))
         (name (splotch-api-get-item-name selected-playlist))
         (buffer (get-buffer-create (format "*Playlist Tracks: %s*" name))))
    (with-current-buffer buffer
      (splotch-track-search-mode)
      (setq-local splotch-selected-playlist selected-playlist)
      (splotch-track-playlist-tracks-update 1))))

(defun splotch-playlist-set-list-format ()
  "Configures the column data for the typical playlist view."
  (setq tabulated-list-format
        (vector `("Playlist Name" ,(- (window-width) 45) t)
                '("Owner Id" 30 t)
                '("# Tracks" 8 (lambda (row-1 row-2)
                                 (< (splotch-api-get-playlist-track-count (car row-1))
                                    (splotch-api-get-playlist-track-count (car row-2)))) :right-align t))))

(defun splotch-playlist-search-print (playlists page)
  "Append PLAYLISTS to PAGE of the current playlist view."
  (let (entries)
    (dolist (playlist playlists)
      (when-let ((_ (hash-table-p playlist))
                 (user-id (splotch-api-get-playlist-owner-id playlist))
                 (playlist-name (splotch-api-get-item-name playlist)))
        (push (list playlist
                    (vector (cons playlist-name
                                  (list 'face 'link
                                        'follow-link t
                                        'action `(lambda (_) (splotch-playlist-tracks))
                                        'help-echo (format "Show %s's tracks" playlist-name)))
                            (cons user-id
                                  (list 'face 'link
                                        'follow-link t
                                        'action `(lambda (_) (splotch-user-playlists ,user-id))
                                        'help-echo (format "Show %s's public playlists" user-id)))
                            (number-to-string (splotch-api-get-playlist-track-count playlist))))
              entries)))
    (when (eq 1 page) (setq-local tabulated-list-entries nil))
    (splotch-playlist-set-list-format)
    (setq-local tabulated-list-entries (append tabulated-list-entries (nreverse entries)))
    (tabulated-list-init-header)
    (tabulated-list-print t)))

(provide 'splotch-playlist)
;;; splotch-playlist.el ends here
