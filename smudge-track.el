;;; smudge-track.el --- Smudge track search major mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library implements UI and a major mode for searching and acting on
;; Spotify playlists.

;;; Code:

(require 'smudge-api)
(require 'smudge-controller)

(defvar smudge-current-page)
(defvar smudge-query)
(defvar smudge-selected-album)
(defvar smudge-recently-played)
(defvar smudge-my-library)

(defvar smudge-track-search-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "M-RET") #'smudge-track-select)
    (define-key map (kbd "a")     #'smudge-track-add)
    (define-key map (kbd "r")     #'smudge-track-remove)
    (define-key map (kbd "l")     #'smudge-track-load-more)
    (define-key map (kbd "g")     #'smudge-track-reload)
    (define-key map (kbd "f")     #'smudge-track-playlist-follow)
    (define-key map (kbd "u")     #'smudge-track-playlist-unfollow)
    (define-key map (kbd "k")     #'smudge-track-add-to-queue)
    map)
  "Local keymap for `smudge-track-search-mode' buffers.")

(define-derived-mode smudge-track-search-mode tabulated-list-mode "Track-Search"
  "Major mode for displaying the track listing returned by a Spotify search.")

(defun smudge-track-select ()
  "Play the track, album or artist under the cursor.
If the cursor is on a button representing an artist or album, start playing that
 artist or album.  Otherwise, play the track selected."
  (interactive)
  (let ((button-type (smudge-track-selected-button-type)))
    (cond ((eq 'artist button-type)
           (smudge-track-artist-select))
          ((eq 'album button-type)
           (smudge-track-album-select))
          (t (smudge-track-select-default)))))

(defun smudge-track-select-default ()
  "Play the track under the cursor.
If the track list represents a playlist, the given track is played in the
context of that playlist; if the track list represents an album, the given
track is played in the context of that album.  Otherwise, it will be played
without a context."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (context (cond ((bound-and-true-p smudge-selected-playlist) smudge-selected-playlist)
                        ((bound-and-true-p smudge-selected-album) smudge-selected-album)
                        (t nil))))
    (smudge-controller-play-track track context)))

(defun smudge-track-selected-button-type ()
  "Get the type of button under the cursor."
  (let ((selected-button (button-at (point))))
    (when selected-button
      (button-get selected-button 'artist-or-album))))

(defun smudge-track-artist-select ()
  "Plays the artist of the track under the cursor."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (artist (smudge-api-get-track-artist track)))
    (smudge-controller-play-track track artist)))

(defun smudge-track-album-select ()
  "Plays the album of the track under the cursor."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (album (smudge-api-get-track-album track)))
    (smudge-controller-play-track track album)))

(defun smudge-track-playlist-follow ()
  "Add the current user as the follower of the selected playlist."
  (interactive)
  (if (bound-and-true-p smudge-selected-playlist)
      (let ((playlist smudge-selected-playlist))
        (when (y-or-n-p (format "Follow playlist '%s'? " (smudge-api-get-item-name playlist)))
          (smudge-api-playlist-follow
           playlist
           (lambda (_)
             (message "Followed playlist '%s'" (smudge-api-get-item-name playlist))))))
    (message "Cannot Follow a playlist from here")))

(defun smudge-track-playlist-unfollow ()
  "Remove the current user as the follower of the selected playlist."
  (interactive)
  (if (bound-and-true-p smudge-selected-playlist)
      (let ((playlist smudge-selected-playlist))
        (when (y-or-n-p (format "Unfollow playlist '%s'? " (smudge-api-get-item-name playlist)))
          (smudge-api-playlist-unfollow
           playlist
           (lambda (_)
             (message "Unfollowed playlist '%s'" (smudge-api-get-item-name playlist))))))
    (message "Cannot unfollow a playlist from here")))

(defun smudge-track-reload ()
  "Reloads the first page of results for the current track view."
  (interactive)
  (cond ((bound-and-true-p smudge-recently-played)
         (smudge-track-recently-played-tracks-update 1))
        ((bound-and-true-p smudge-my-library)
         (smudge-track-recently-played-tracks-update 1))
        ((bound-and-true-p smudge-selected-playlist)
         (smudge-track-playlist-tracks-update 1))
        ((bound-and-true-p smudge-query)
         (smudge-track-search-update smudge-query 1))
        ((bound-and-true-p smudge-selected-album)
         (smudge-track-album-tracks-update smudge-selected-album 1))))

(defun smudge-track-load-more ()
  "Load the next page of results for the current track view."
  (interactive)
  (cond ((bound-and-true-p smudge-recently-played)
         (smudge-track-recently-played-tracks-update (1+ smudge-current-page)))
        ((bound-and-true-p smudge-my-library)
         (smudge-track-my-library-update (1+ smudge-current-page)))
        ((bound-and-true-p smudge-selected-playlist)
         (smudge-track-playlist-tracks-update (1+ smudge-current-page)))
        ((bound-and-true-p smudge-selected-album)
         (smudge-track-album-tracks-update smudge-selected-album (1+ smudge-current-page)))
        ((bound-and-true-p smudge-query)
         (smudge-track-search-update smudge-query (1+ smudge-current-page)))))

(defun smudge-track-search-update (query page)
  "Fetch the PAGE of results using QUERY at the search endpoint."
  (let ((buffer (current-buffer)))
    (smudge-api-search
     'track
     query
     page
     (lambda (json)
       (if-let ((items (smudge-api-get-search-track-items json)))
           (with-current-buffer buffer
             (setq-local smudge-current-page page)
             (setq-local smudge-query query)
             (pop-to-buffer buffer)
             (smudge-track-search-print items page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun smudge-track-playlist-tracks-update (page)
  "Fetch PAGE of results for the current playlist."
  (when (bound-and-true-p smudge-selected-playlist)
    (let ((buffer (current-buffer)))
      (smudge-api-playlist-tracks
       smudge-selected-playlist
       page
       (lambda (json)
         (if-let ((items (smudge-api-get-playlist-tracks json)))
             (with-current-buffer buffer
               (setq-local smudge-current-page page)
               (pop-to-buffer buffer)
               (smudge-track-search-print items page)
               (message "Track view updated"))
           (message "No more tracks")))))))

(defun smudge-track-album-tracks-update (album page)
  "Fetch PAGE of of tracks for ALBUM."
  (let ((buffer (current-buffer)))
    (smudge-api-album-tracks
     album
     page
     (lambda (json)
       (if-let ((items (smudge-api-get-items json)))
           (with-current-buffer buffer
             (setq-local smudge-current-page page)
             (setq-local smudge-selected-album album)
             (pop-to-buffer buffer)
             (smudge-track-search-print items page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun smudge-track-recently-played-tracks-update (page)
  "Fetch PAGE of results for the recently played tracks."
  (let ((buffer (current-buffer)))
    (smudge-api-recently-played
     page
     (lambda (json)
       (if-let ((items (smudge-api-get-playlist-tracks json)))
           (with-current-buffer buffer
             (setq-local smudge-current-page page)
             (setq-local smudge-recently-played t)
             (pop-to-buffer buffer)
             (smudge-track-search-print items page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun smudge-track-my-library-update (page)
  "Fetch PAGE of results from the user's Liked Songs."
  (let ((buffer (current-buffer)))
    (smudge-api-get-my-library-tracks
     page
     (lambda (json)
       (if-let ((items (smudge-api-get-items json))
                (tracks (mapcar (lambda (item) (gethash "track" item))
                                items)))
           (with-current-buffer buffer
             (setq-local smudge-current-page page)
             (setq-local smudge-my-library t)
             (pop-to-buffer buffer)
             (smudge-track-search-print tracks page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun smudge-track-search-set-list-format ()
  "Configure the column data for the typical track view.
Default to sortin tracks by number when listing the tracks from an album."
  (let* ((base-width (truncate (/ (- (window-width) 30) 3)))
         (default-width (if (bound-and-true-p smudge-selected-album) (+ base-width 4) base-width )))
    (unless (or
             (bound-and-true-p smudge-selected-playlist)
             (bound-and-true-p smudge-my-library))
      (setq tabulated-list-sort-key `("#" . nil)))
    ;; Feb-2026 removed Track `popularity'; that column was always empty, so it
    ;; was replaced with "Added" (the date the track was added to the playlist),
    ;; shown only in playlist views (search/album results have no such date).
    (setq tabulated-list-format
          (vconcat (vector `("#" 3 ,(lambda (row-1 row-2)
                                      (< (+ (* 100 (smudge-api-get-disc-number (car row-1)))
                                            (smudge-api-get-track-number (car row-1)))
                                         (+ (* 100 (smudge-api-get-disc-number (car row-2)))
                                            (smudge-api-get-track-number (car row-2))))) :right-align t)
                           `("Track Name" ,default-width t)
                           `("Artist" ,default-width t)
                           `("Album" ,default-width t)
                           `("Time" 8 (lambda (row-1 row-2)
                                        (< (smudge-get-track-duration (car row-1))
                                           (smudge-get-track-duration (car row-2))))))
                   (when (bound-and-true-p smudge-selected-playlist)
                     (vector '("Added" 12 t)))))))

(defun smudge-track-added-date (song)
  "Return SONG's playlist `added_at' as a YYYY-MM-DD string, or an empty string.
The timestamp is stashed on the track by `smudge-api-get-playlist-tracks'."
  (let ((added (and (hash-table-p song) (gethash "added_at" song))))
    (if (stringp added)
        (condition-case nil
            (format-time-string "%Y-%m-%d" (date-to-time added))
          (error (substring added 0 (min 10 (length added)))))
      "")))

(defun smudge-track-search-print (songs page)
  "Append SONGS to the PAGE of track view."
  (let (entries)
    (dolist (song songs)
      (when (and (hash-table-p song) (smudge-api-is-track-playable song))
        (let* ((artist-name (smudge-api-get-track-artist-name song))
               (album (or (smudge-api-get-track-album song) smudge-selected-album))
               (album-name (smudge-api-get-item-name album))
               (album (smudge-api-get-track-album song)))
          (push (list song
                      (vector (number-to-string (smudge-api-get-track-number song))
                              (smudge-api-get-item-name song)
                              (cons artist-name
                                    (list 'face 'link
                                          'follow-link t
                                          'action `(lambda (_) (smudge-track-search ,(format "artist:\"%s\"" artist-name)))
                                          'help-echo (format "Show %s's tracks" artist-name)
                                          'artist-or-album 'artist))
                              (cons album-name
                                    (list 'face 'link
                                          'follow-link t
                                          'action `(lambda (_) (smudge-track-album-tracks ,album))
                                          'help-echo (format "Show %s's tracks" album-name)
                                          'artist-or-album 'album))
                              (smudge-api-get-track-duration-formatted song)
                              (when (bound-and-true-p smudge-selected-playlist)
                                (smudge-track-added-date song))))
                entries))))
    (smudge-track-search-set-list-format)
    (when (eq 1 page) (setq-local tabulated-list-entries nil))
    (setq-local tabulated-list-entries (append tabulated-list-entries (nreverse entries)))
    (tabulated-list-init-header)
    (tabulated-list-print t)))

(defun smudge-track-album-tracks (album)
  "Open a new buffer that lists the tracks from ALBUM."
  (let ((buffer (get-buffer-create (format "*Album: %s*" (smudge-api-get-item-name album)))))
    (with-current-buffer buffer
      (smudge-track-search-mode)
      (smudge-track-album-tracks-update album 1))))

(defun smudge-track--collect-modifiable-playlists (user-id page acc callback)
  "Accumulate all of USER-ID's modifiable playlists across pages, then CALLBACK.
Start at PAGE, accumulating (NAME ID) entries into ACC.  A playlist is
modifiable if USER-ID owns it or it is collaborative; followed playlists are
skipped because the API rejects writes to them.  Pages are followed until one
comes back not full, so every playlist is offered (not just the first page)."
  (smudge-api-user-playlists
   user-id page
   (lambda (json)
     (let* ((items (smudge-api-get-items json))
            (acc (append acc
                         (delq nil
                               (mapcar
                                (lambda (a)
                                  (when (or (equal user-id (smudge-api-get-playlist-owner-id a))
                                            (eq t (gethash "collaborative" a)))
                                    (list (smudge-api-get-item-name a) (smudge-api-get-item-id a))))
                                items)))))
       (if (and items (= (length items) smudge-api-search-limit))
           (smudge-track--collect-modifiable-playlists user-id (1+ page) acc callback)
         (funcall callback acc))))))

(defun smudge-track-select-playlist (callback)
  "Call CALLBACK with the id of a playlist the user selects.
Only playlists the user can modify (owned or collaborative) are offered, since
the API rejects adding to a playlist you merely follow.  All pages of your
playlists are gathered before prompting."
  (interactive)
  (smudge-api-current-user
   (lambda (user)
     (smudge-track--collect-modifiable-playlists
      (smudge-api-get-item-id user) 1 nil
      (lambda (choices)
        (if (null choices)
            (message "No modifiable playlists found (owned or collaborative)")
          (let ((selected (completing-read "Select Playlist: " choices nil t)))
            (unless (string= "" selected)
              (funcall callback (cadr (assoc selected choices)))))))))))

(defun smudge-track-add ()
  "Add the track under the cursor on a playlist.  Prompt for the playlist."
  (interactive)
  (let ((selected-track (tabulated-list-get-id)))
    (smudge-track-select-playlist
     (lambda (playlist)
       (smudge-api-current-user
        (lambda (user)
          (smudge-api-playlist-add-track
           (smudge-api-get-item-id user)
           playlist
           (smudge-api-get-item-uri selected-track)
           (lambda (_)
             (message "Song added.")))))))))

(defun smudge-track-remove ()
  "Remove the track under the cursor from the selected playlist."
  (interactive)
  (if (bound-and-true-p smudge-selected-playlist)
      (let ((playlist (smudge-api-get-item-id smudge-selected-playlist))
            (selected-track (tabulated-list-get-id)))
        (smudge-api-playlist-remove-track
         playlist
         (smudge-api-get-item-uri selected-track)
         (lambda (_)
           (message "Song removed."))))
    (message "Cannot remove a track from a playlist from here")))

(defun smudge-track-add-to-queue ()
  "Add the track(s) under the cursor (or inside the active region) to the queue."
  (interactive)
  ;; Check whether the mark is active and if so, queue all the tracks in the
  ;; region. If not, queue the track under the cursor.
  (if (null mark-active)
      (let ((track-at-point (tabulated-list-get-id)))
        (smudge-api-queue-add-track
         (smudge-api-get-item-uri track-at-point)
         (lambda(_)
           (message "Added \"%s\" to your queue." (smudge-api-get-item-name track-at-point)))))
    (let ((start (region-beginning))
          (end (region-end))
          (tracks '()))
      (save-excursion
        (goto-char start)
        (while (< (point) end)
          (setq tracks (cons (smudge-api-get-item-uri (tabulated-list-get-id)) tracks))
          (forward-line 1)))
      (smudge-api-queue-add-tracks
       (reverse tracks)
       nil)
      ;; Send the message here instead of in the callback
      ;; because the API call has to sequentially add each song which might take some time.
      (message "Added %d tracks to your queue." (length tracks)))))

(defun smudge-save-playing-track-to-library ()
  "Save the currently playing track to Liked Songs."
  (interactive)
  (smudge-api-get-player-status
   (lambda (status)
     (when-let* ((status status)
                 (track (gethash "item" status))
                 (id (gethash "id" track)))
       (smudge-api-save-tracks-to-my-library
        (list id)
        (lambda (_)
          (message "Liked song: %s - %s"
                   (gethash "name" (car (gethash "artists" track)))
                   (gethash "name" track))))))))

(defun smudge-remove-playing-track-from-library ()
  "Save the currently playing track to Liked Songs."
  (interactive)
  (smudge-api-get-player-status
   (lambda (status)
     (when-let* ((status status)
                 (track (gethash "item" status))
                 (id (gethash "id" track)))
       (smudge-api-remove-tracks-from-my-library
        (list id)
        (lambda (_)
          (message "Removed song: %s - %s"
                   (gethash "name" (car (gethash "artists" track)))
                   (gethash "name" track))))))))

(defun smudge-add-playing-track-to-playlist ()
  "Add the currently playing track to one of your playlists.
Prompts with completion for a playlist you can modify (owned or collaborative)."
  (interactive)
  (smudge-api-get-player-status
   (lambda (status)
     (let* ((track (and (hash-table-p status) (gethash "item" status)))
            (track-id (and (hash-table-p track) (gethash "id" track)))
            (track-name (and (hash-table-p track) (smudge-api-get-item-name track))))
       (if (not track-id)
           (message "No currently playing track to add")
         (smudge-track-select-playlist
          (lambda (playlist-id)
            (smudge-api-playlist-add-tracks
             nil playlist-id (list track-id)
             (lambda (_)
               (message "Added \"%s\" to the selected playlist" track-name))))))))))


(provide 'smudge-track)
;;; smudge-track.el ends here
