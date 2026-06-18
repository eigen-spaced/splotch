;;; splotch-track.el --- Splotch track search major mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library implements UI and a major mode for searching and acting on
;; Spotify playlists.

;;; Code:

(require 'splotch-api)
(require 'splotch-controller)

(defvar splotch-current-page)
(defvar splotch-query)
(defvar splotch-selected-album)
(defvar splotch-recently-played)
(defvar splotch-my-library)

(defvar splotch-track-search-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "M-RET") #'splotch-track-select)
    (define-key map (kbd "a")     #'splotch-track-add)
    (define-key map (kbd "r")     #'splotch-track-remove)
    (define-key map (kbd "l")     #'splotch-track-load-more)
    (define-key map (kbd "g")     #'splotch-track-reload)
    (define-key map (kbd "f")     #'splotch-track-playlist-follow)
    (define-key map (kbd "u")     #'splotch-track-playlist-unfollow)
    (define-key map (kbd "k")     #'splotch-track-add-to-queue)
    map)
  "Local keymap for `splotch-track-search-mode' buffers.")

(define-derived-mode splotch-track-search-mode tabulated-list-mode "Track-Search"
  "Major mode for displaying the track listing returned by a Spotify search.")

(defun splotch-track-select ()
  "Play the track, album or artist under the cursor.
If the cursor is on a button representing an artist or album, start playing that
 artist or album.  Otherwise, play the track selected."
  (interactive)
  (let ((button-type (splotch-track-selected-button-type)))
    (cond ((eq 'artist button-type)
           (splotch-track-artist-select))
          ((eq 'album button-type)
           (splotch-track-album-select))
          (t (splotch-track-select-default)))))

(defun splotch-track-select-default ()
  "Play the track under the cursor.
If the track list represents a playlist, the given track is played in the
context of that playlist; if the track list represents an album, the given
track is played in the context of that album.  Otherwise, it will be played
without a context."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (context (cond ((bound-and-true-p splotch-selected-playlist) splotch-selected-playlist)
                        ((bound-and-true-p splotch-selected-album) splotch-selected-album)
                        (t nil))))
    (splotch-controller-play-track track context)))

(defun splotch-track-selected-button-type ()
  "Get the type of button under the cursor."
  (let ((selected-button (button-at (point))))
    (when selected-button
      (button-get selected-button 'artist-or-album))))

(defun splotch-track-artist-select ()
  "Plays the artist of the track under the cursor."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (artist (splotch-api-get-track-artist track)))
    (splotch-controller-play-track track artist)))

(defun splotch-track-album-select ()
  "Plays the album of the track under the cursor."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (album (splotch-api-get-track-album track)))
    (splotch-controller-play-track track album)))

(defun splotch-track-playlist-follow ()
  "Add the current user as the follower of the selected playlist."
  (interactive)
  (if (bound-and-true-p splotch-selected-playlist)
      (let ((playlist splotch-selected-playlist))
        (when (y-or-n-p (format "Follow playlist '%s'? " (splotch-api-get-item-name playlist)))
          (splotch-api-playlist-follow
           playlist
           (lambda (_)
             (message "Followed playlist '%s'" (splotch-api-get-item-name playlist))))))
    (message "Cannot Follow a playlist from here")))

(defun splotch-track-playlist-unfollow ()
  "Remove the current user as the follower of the selected playlist."
  (interactive)
  (if (bound-and-true-p splotch-selected-playlist)
      (let ((playlist splotch-selected-playlist))
        (when (y-or-n-p (format "Unfollow playlist '%s'? " (splotch-api-get-item-name playlist)))
          (splotch-api-playlist-unfollow
           playlist
           (lambda (_)
             (message "Unfollowed playlist '%s'" (splotch-api-get-item-name playlist))))))
    (message "Cannot unfollow a playlist from here")))

(defun splotch-track-reload ()
  "Reloads the first page of results for the current track view."
  (interactive)
  (cond ((bound-and-true-p splotch-recently-played)
         (splotch-track-recently-played-tracks-update 1))
        ((bound-and-true-p splotch-my-library)
         (splotch-track-recently-played-tracks-update 1))
        ((bound-and-true-p splotch-selected-playlist)
         (splotch-track-playlist-tracks-update 1))
        ((bound-and-true-p splotch-query)
         (splotch-track-search-update splotch-query 1))
        ((bound-and-true-p splotch-selected-album)
         (splotch-track-album-tracks-update splotch-selected-album 1))))

(defun splotch-track-load-more ()
  "Load the next page of results for the current track view."
  (interactive)
  (cond ((bound-and-true-p splotch-recently-played)
         (splotch-track-recently-played-tracks-update (1+ splotch-current-page)))
        ((bound-and-true-p splotch-my-library)
         (splotch-track-my-library-update (1+ splotch-current-page)))
        ((bound-and-true-p splotch-selected-playlist)
         (splotch-track-playlist-tracks-update (1+ splotch-current-page)))
        ((bound-and-true-p splotch-selected-album)
         (splotch-track-album-tracks-update splotch-selected-album (1+ splotch-current-page)))
        ((bound-and-true-p splotch-query)
         (splotch-track-search-update splotch-query (1+ splotch-current-page)))))

(defun splotch-track-search-update (query page)
  "Fetch the PAGE of results using QUERY at the search endpoint."
  (let ((buffer (current-buffer)))
    (splotch-api-search
     'track
     query
     page
     (lambda (json)
       (if-let ((items (splotch-api-get-search-track-items json)))
           (with-current-buffer buffer
             (setq-local splotch-current-page page)
             (setq-local splotch-query query)
             (pop-to-buffer buffer)
             (splotch-track-search-print items page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun splotch-track-playlist-tracks-update (page)
  "Fetch PAGE of results for the current playlist."
  (when (bound-and-true-p splotch-selected-playlist)
    (let ((buffer (current-buffer)))
      (splotch-api-playlist-tracks
       splotch-selected-playlist
       page
       (lambda (json)
         (if-let ((items (splotch-api-get-playlist-tracks json)))
             (with-current-buffer buffer
               (setq-local splotch-current-page page)
               (pop-to-buffer buffer)
               (splotch-track-search-print items page)
               (message "Track view updated"))
           (message "No more tracks")))))))

(defun splotch-track-album-tracks-update (album page)
  "Fetch PAGE of of tracks for ALBUM."
  (let ((buffer (current-buffer)))
    (splotch-api-album-tracks
     album
     page
     (lambda (json)
       (if-let ((items (splotch-api-get-items json)))
           (with-current-buffer buffer
             (setq-local splotch-current-page page)
             (setq-local splotch-selected-album album)
             (pop-to-buffer buffer)
             (splotch-track-search-print items page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun splotch-track-recently-played-tracks-update (page)
  "Fetch PAGE of results for the recently played tracks."
  (let ((buffer (current-buffer)))
    (splotch-api-recently-played
     page
     (lambda (json)
       (if-let ((items (splotch-api-get-playlist-tracks json)))
           (with-current-buffer buffer
             (setq-local splotch-current-page page)
             (setq-local splotch-recently-played t)
             (pop-to-buffer buffer)
             (splotch-track-search-print items page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun splotch-track-my-library-update (page)
  "Fetch PAGE of results from the user's Liked Songs."
  (let ((buffer (current-buffer)))
    (splotch-api-get-my-library-tracks
     page
     (lambda (json)
       (if-let ((items (splotch-api-get-items json))
                (tracks (mapcar (lambda (item) (gethash "track" item))
                                items)))
           (with-current-buffer buffer
             (setq-local splotch-current-page page)
             (setq-local splotch-my-library t)
             (pop-to-buffer buffer)
             (splotch-track-search-print tracks page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun splotch-track-search-set-list-format ()
  "Configure the column data for the typical track view.
Default to sortin tracks by number when listing the tracks from an album."
  (let* ((base-width (truncate (/ (- (window-width) 30) 3)))
         (default-width (if (bound-and-true-p splotch-selected-album) (+ base-width 4) base-width )))
    (unless (or
             (bound-and-true-p splotch-selected-playlist)
             (bound-and-true-p splotch-my-library))
      (setq tabulated-list-sort-key `("#" . nil)))
    ;; Feb-2026 removed Track `popularity' (column always empty); playlist views
    ;; show "Added" (date added) instead — search/album views have no such date.
    (setq tabulated-list-format
          (vconcat (vector `("#" 3 ,(lambda (row-1 row-2)
                                      (< (+ (* 100 (splotch-api-get-disc-number (car row-1)))
                                            (splotch-api-get-track-number (car row-1)))
                                         (+ (* 100 (splotch-api-get-disc-number (car row-2)))
                                            (splotch-api-get-track-number (car row-2))))) :right-align t)
                           `("Track Name" ,default-width t)
                           `("Artist" ,default-width t)
                           `("Album" ,default-width t)
                           `("Time" 8 (lambda (row-1 row-2)
                                        (< (splotch-get-track-duration (car row-1))
                                           (splotch-get-track-duration (car row-2))))))
                   (when (bound-and-true-p splotch-selected-playlist)
                     (vector '("Added" 12 t)))))))

(defun splotch-track-added-date (song)
  "Return SONG's playlist `added_at' as a YYYY-MM-DD string, or an empty string.
The timestamp is stashed on the track by `splotch-api-get-playlist-tracks'."
  (let ((added (and (hash-table-p song) (gethash "added_at" song))))
    (if (stringp added)
        (condition-case nil
            (format-time-string "%Y-%m-%d" (date-to-time added))
          (error (substring added 0 (min 10 (length added)))))
      "")))

(defun splotch-track-search-print (songs page)
  "Append SONGS to the PAGE of track view."
  (let (entries)
    (dolist (song songs)
      (when (and (hash-table-p song) (splotch-api-is-track-playable song))
        (let* ((artist-name (splotch-api-get-track-artist-name song))
               (album (or (splotch-api-get-track-album song) splotch-selected-album))
               (album-name (splotch-api-get-item-name album))
               (album (splotch-api-get-track-album song)))
          (push (list song
                      (vector (number-to-string (splotch-api-get-track-number song))
                              (splotch-api-get-item-name song)
                              (cons artist-name
                                    (list 'face 'link
                                          'follow-link t
                                          'action `(lambda (_) (splotch-track-search ,(format "artist:\"%s\"" artist-name)))
                                          'help-echo (format "Show %s's tracks" artist-name)
                                          'artist-or-album 'artist))
                              (cons album-name
                                    (list 'face 'link
                                          'follow-link t
                                          'action `(lambda (_) (splotch-track-album-tracks ,album))
                                          'help-echo (format "Show %s's tracks" album-name)
                                          'artist-or-album 'album))
                              (splotch-api-get-track-duration-formatted song)
                              (when (bound-and-true-p splotch-selected-playlist)
                                (splotch-track-added-date song))))
                entries))))
    (splotch-track-search-set-list-format)
    (when (eq 1 page) (setq-local tabulated-list-entries nil))
    (setq-local tabulated-list-entries (append tabulated-list-entries (nreverse entries)))
    (tabulated-list-init-header)
    (tabulated-list-print t)))

(defun splotch-track-album-tracks (album)
  "Open a new buffer that lists the tracks from ALBUM."
  (let ((buffer (get-buffer-create (format "*Album: %s*" (splotch-api-get-item-name album)))))
    (with-current-buffer buffer
      (splotch-track-search-mode)
      (splotch-track-album-tracks-update album 1))))

(defun splotch-track--collect-modifiable-playlists (user-id page acc callback)
  "Accumulate USER-ID's modifiable (owned or collaborative) playlists across all
pages into ACC as (NAME ID) entries, starting at PAGE, then call CALLBACK."
  (splotch-api-user-playlists
   user-id page
   (lambda (json)
     (let* ((items (splotch-api-get-items json))
            (acc (append acc
                         (delq nil
                               (mapcar
                                (lambda (a)
                                  (when (or (equal user-id (splotch-api-get-playlist-owner-id a))
                                            (eq t (gethash "collaborative" a)))
                                    (list (splotch-api-get-item-name a) (splotch-api-get-item-id a))))
                                items)))))
       (if (and items (= (length items) splotch-api-search-limit))
           (splotch-track--collect-modifiable-playlists user-id (1+ page) acc callback)
         (funcall callback acc))))))

(defun splotch-track-select-playlist (callback)
  "Prompt for one of the user's modifiable playlists, then call CALLBACK with its id.
Only owned or collaborative playlists are offered (you can't add to a followed one)."
  (interactive)
  (splotch-api-current-user
   (lambda (user)
     (splotch-track--collect-modifiable-playlists
      (splotch-api-get-item-id user) 1 nil
      (lambda (choices)
        (if (null choices)
            (message "No modifiable playlists found (owned or collaborative)")
          (let* ((selected (completing-read "Select Playlist: " choices nil t))
                 (id (cadr (assoc selected choices))))
            ;; A selection that doesn't resolve to an id (raw input past
            ;; require-match) would crash downstream in `url-hexify-string'.
            (if (and (stringp id) (not (string-empty-p id)))
                (funcall callback id)
              (message "No playlist selected")))))))))

(defun splotch-track-add ()
  "Add the track under the cursor on a playlist.  Prompt for the playlist."
  (interactive)
  (let ((selected-track (tabulated-list-get-id)))
    (splotch-track-select-playlist
     (lambda (playlist)
       (splotch-api-current-user
        (lambda (user)
          (splotch-api-playlist-add-track
           (splotch-api-get-item-id user)
           playlist
           (splotch-api-get-item-uri selected-track)
           (lambda (_)
             (message "Song added.")))))))))

(defun splotch-track-remove ()
  "Remove the track under the cursor from the selected playlist."
  (interactive)
  (if (bound-and-true-p splotch-selected-playlist)
      (let ((playlist (splotch-api-get-item-id splotch-selected-playlist))
            (selected-track (tabulated-list-get-id)))
        (splotch-api-playlist-remove-track
         playlist
         (splotch-api-get-item-uri selected-track)
         (lambda (_)
           (message "Song removed."))))
    (message "Cannot remove a track from a playlist from here")))

(defun splotch-track-add-to-queue ()
  "Add the track(s) under the cursor (or inside the active region) to the queue."
  (interactive)
  ;; Check whether the mark is active and if so, queue all the tracks in the
  ;; region. If not, queue the track under the cursor.
  (if (null mark-active)
      (let ((track-at-point (tabulated-list-get-id)))
        (splotch-api-queue-add-track
         (splotch-api-get-item-uri track-at-point)
         (lambda(_)
           (message "Added \"%s\" to your queue." (splotch-api-get-item-name track-at-point)))))
    (let ((start (region-beginning))
          (end (region-end))
          (tracks '()))
      (save-excursion
        (goto-char start)
        (while (< (point) end)
          (setq tracks (cons (splotch-api-get-item-uri (tabulated-list-get-id)) tracks))
          (forward-line 1)))
      (splotch-api-queue-add-tracks
       (reverse tracks)
       nil)
      ;; Send the message here instead of in the callback
      ;; because the API call has to sequentially add each song which might take some time.
      (message "Added %d tracks to your queue." (length tracks)))))

(defun splotch-save-playing-track-to-library ()
  "Save the currently playing track to Liked Songs."
  (interactive)
  (splotch-api-get-player-status
   (lambda (status)
     (when-let* ((status status)
                 (track (gethash "item" status))
                 (id (gethash "id" track)))
       (splotch-api-save-tracks-to-my-library
        (list id)
        (lambda (_)
          (message "Liked song: %s - %s"
                   (gethash "name" (car (gethash "artists" track)))
                   (gethash "name" track))))))))

(defun splotch-remove-playing-track-from-library ()
  "Remove the currently playing track from Liked Songs."
  (interactive)
  (splotch-api-get-player-status
   (lambda (status)
     (when-let* ((status status)
                 (track (gethash "item" status))
                 (id (gethash "id" track)))
       (splotch-api-remove-tracks-from-my-library
        (list id)
        (lambda (_)
          (message "Removed song: %s - %s"
                   (gethash "name" (car (gethash "artists" track)))
                   (gethash "name" track))))))))

(defun splotch-add-playing-track-to-playlist ()
  "Add the currently playing track to one of your playlists.
Prompts with completion for a playlist you can modify (owned or collaborative)."
  (interactive)
  (splotch-api-get-player-status
   (lambda (status)
     (let* ((track (and (hash-table-p status) (gethash "item" status)))
            (track-id (and (hash-table-p track) (gethash "id" track)))
            (track-name (and (hash-table-p track) (splotch-api-get-item-name track))))
       (if (not track-id)
           (message "No currently playing track to add")
         (splotch-track-select-playlist
          (lambda (playlist-id)
            (splotch-api-playlist-add-tracks
             nil playlist-id (list track-id)
             (lambda (_)
               (message "Added \"%s\" to the selected playlist" track-name))))))))))


(provide 'splotch-track)
;;; splotch-track.el ends here
