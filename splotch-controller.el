;;; splotch-controller.el --- Generic player controller interface for Splotch  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library defines a set of commands for controlling an instance of a
;; Spotify client. The commands are sent via a multimethod-like dispatch to
;; the chosen transport.

;;; Code:

(require 'splotch-api)

(defmacro splotch-if-gnu-linux (then else)
  "Evaluate THEN form if Emacs is running in Linux, otherwise evaluate ELSE."
  `(if (eq system-type 'gnu/linux) ,then ,else))

(defmacro splotch-when-gnu-linux (then)
  "Evaluate THEN form if Emacs is running in GNU/Linux."
  `(splotch-if-gnu-linux ,then nil))

(defmacro splotch-if-darwin (then else)
  "Evaluate THEN form if Emacs is running in OS X, otherwise evaluate ELSE form."
  `(if (eq system-type 'darwin) ,then ,else))

(defmacro splotch-when-darwin (then)
  "Evaluate THEN form if Emacs is running in OS X."
  `(splotch-if-darwin ,then nil))

(defcustom splotch-transport 'connect
  "How the commands should be sent to Spotify process.
Defaults to \\='connect, as it provides a consistent UX across all OSes."
  :type '(choice (symbol :tag "AppleScript" apple)
          (symbol :tag "D-Bus" dbus)
          (symbol :tag "Connect" connect))
  :group 'splotch)

(defcustom splotch-player-status-refresh-interval 5
  "The interval, in seconds, that the mode line must be updated.
When using the'connect transport, avoid using values smaller than 5
to avoid being rate limited.  Set to 0 to disable this feature."
  :type 'integer
  :group 'splotch)

(defcustom splotch-player-status-truncate-length 15
  "The maximum number of characters to truncate fields.
Fields will be truncated in `splotch-controller-player-status-format'."
  :type 'integer
  :group 'splotch)

(defcustom splotch-player-status-playing-text "Playing"
  "Text to be displayed when Spotify is playing."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-paused-text "Paused"
  "Text to be displayed when Spotify is paused."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-stopped-text "Stopped"
  "Text to be displayed when Spotify is stopped."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-repeating-text "R"
  "Text to be displayed when repeat is enabled."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-not-repeating-text "-"
  "Text to be displayed when repeat is disabled."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-shuffling-text "S"
  "Text to be displayed when shuffling is enabled."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-not-shuffling-text "-"
  "Text to be displayed when shuffling is disabled."
  :type 'string
  :group 'splotch)

(defcustom splotch-player-status-format "[%p: %a - %t ◷ %l %r%s]"
  "Format used to display the current Spotify client player status.
The following placeholders are supported:

* %a - Artist name (truncated)
* %t - Track name (truncated)
* %n - Track #
* %l - Track duration, in minutes (i.e. 01:35)
* %p - Player status indicator for playing, paused, and stopped states
* %s - Player shuffling status indicator
* %r - Player repeating status indicator"
  :type 'string
  :group 'splotch)

(defcustom splotch-player-use-transient-map nil
  "Whether to activate a transient map for commands likely to be repeated."
  :type 'bool
  :group 'splotch)

(defcustom splotch-controller-metadata-hook nil
  "Hook run after the player metadata is updated.
Each function is called with one argument, the metadata hash table or nil."
  :type 'hook
  :group 'splotch)

(defvar splotch-controller-timer nil
  "Holds the timer object used to refresh the modeline.")

(defvar splotch-controller-player-status ""
  "The text to be displayed in the global mode line or title bar.")

(defvar splotch-controller-player-metadata nil
  "The metadata about the currently playing track.")

(defvar splotch-transient-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "b") #'splotch-controller-previous-track)
    (define-key map (kbd "n") #'splotch-controller-next-track)
    (define-key map (kbd "u") #'splotch-controller-volume-up)
    (define-key map (kbd "d") #'splotch-controller-volume-down)
    map)
  "Transient keymap for commands that are likely to be repeated.")

(defmacro defun-splotch-transient (&rest body)
  "Create a transient splotch command from BODY.

A transient command allows you to immediately invoke another command from
`splotch-transient-command-map'. See `set-transient-map'.

The transient map is enabled if `splotch-player-use-transient-map' is non-nil."
  (declare (doc-string 3)
           (indent defun))
  `(defun ,@body
       (when splotch-player-use-transient-map
         (set-transient-map splotch-transient-command-map))))

(defun splotch-controller-apply (suffix &rest args)
  "Simple facility to emulate multimethods.
Apply SUFFIX to splotch-controller-prefixed functions, applying ARGS."
  (let ((func-name (format "splotch-%s-%s" splotch-transport suffix)))
    (apply (intern func-name) args)
    ;; Schedule status update after control actions, with longer delay for API processing
    (unless (string= suffix "player-status")
      (run-at-time 2 nil #'splotch-controller-player-status))))

(defun splotch-controller-update-metadata (metadata)
  "Build the playing status to be displayed in the mode-line from METADATA."
  (let* ((player-status splotch-player-status-format)
         (duration-format "%m:%02s")
         (json (condition-case nil
                   (json-parse-string
                    metadata
                    :array-type 'list
                    :object-type 'hash-table)
                 (error nil))))
    (if json
        (progn
          (setq player-status (replace-regexp-in-string "%a" (truncate-string-to-width (gethash "artist" json) splotch-player-status-truncate-length 0 nil "...") player-status)
                player-status (replace-regexp-in-string "%t" (truncate-string-to-width (gethash "name" json) splotch-player-status-truncate-length 0 nil "...") player-status)
                player-status (replace-regexp-in-string "%n" (number-to-string (gethash "track_number" json)) player-status)
                player-status (replace-regexp-in-string "%l" (format-seconds duration-format (/ (gethash "duration" json) 1000)) player-status)
                player-status (replace-regexp-in-string "%s" (splotch-controller-player-status-shuffling-indicator (gethash "player_shuffling" json)) player-status)
                player-status (replace-regexp-in-string "%r" (splotch-controller-player-status-repeating-indicator (gethash "player_repeating" json)) player-status)
                player-status (replace-regexp-in-string "%p" (splotch-controller-player-status-playing-indicator (gethash "player_state" json)) player-status))
          (splotch-controller-update-player-status player-status)
          (setq splotch-controller-player-metadata json)
          (run-hook-with-args 'splotch-controller-metadata-hook json))
      (splotch-controller-update-player-status "")
      (run-hook-with-args 'splotch-controller-metadata-hook nil))))

(defun splotch-controller-update-player-status (str)
  "Set the given STR to the player status, prefixed with the mode identifier."
  (unless (string= str splotch-controller-player-status)
    (setq splotch-controller-player-status str)))

(defun splotch-controller-player-status-playing-indicator (str)
  "Return the value of the player state variable.
This value corresponding to the player's current state in STR."
  (cond ((string= "playing" str) splotch-player-status-playing-text)
        ((string= "stopped" str) splotch-player-status-stopped-text)
        ((string= "paused" str) splotch-player-status-paused-text)))

(defun splotch-controller-player-status-shuffling-indicator (shuffling)
  "Return the value of the shuffling state variable.
This value corresponds to the current SHUFFLING state."
  (if (eq shuffling t)
      splotch-player-status-shuffling-text
    splotch-player-status-not-shuffling-text))

(defun splotch-controller-player-status-repeating-indicator (repeating)
  "Return the value of the repeating state variable.
This corresponds to the current REPEATING state."
  (if (eq repeating t)
      splotch-player-status-repeating-text
    splotch-player-status-not-repeating-text))

(defun splotch-controller-timerp ()
  "Predicate to determine if the refresh timer is running."
  (and (boundp 'splotch-controller-timer) (timerp splotch-controller-timer)))

(defun splotch-controller-start-player-status-timer ()
  "Start the timer that will update the mode line with Spotify player status."
  (when (and (not (splotch-controller-timerp)) (> splotch-player-status-refresh-interval 0))
    (setq splotch-controller-timer
          (run-at-time t splotch-player-status-refresh-interval 'splotch-controller-player-status))))

(defun splotch-controller-stop-player-status-timer ()
  "Stop the timer that is updating the mode line."
  (when (splotch-controller-timerp)
    (cancel-timer splotch-controller-timer)
    (setq splotch-controller-timer nil)))

(defun splotch-controller-player-status ()
  "Update the mode line to display the current Spotify player status."
  (interactive)
  (splotch-controller-apply "player-status"))

(defun splotch-controller-play-uri (uri)
  "Sends a `play' command to Spotify process passing the given URI."
  (interactive "SSpotify URI: ")
  (splotch-controller-apply "player-play-track" uri nil))

(defun splotch-controller-play-track (track &optional context)
  "Sends a `play' command to Spotify process with TRACK passing a CONTEXT id."
  (interactive)
  (splotch-controller-apply
   "player-play-track"
   (when track (splotch-api-get-item-uri track))
   (when context (splotch-api-get-item-uri context))))

(defun-splotch-transient splotch-controller-toggle-play ()
  "Sends a `playpause' command to Spotify process."
  (interactive)
  (splotch-controller-apply "player-toggle-play"))

(defun-splotch-transient splotch-controller-next-track ()
  "Sends a `next track' command to Spotify process."
  (interactive)
  (splotch-controller-apply "player-next-track"))

(defun-splotch-transient splotch-controller-previous-track ()
  "Sends a `previous track' command to Spotify process."
  (interactive)
  (splotch-controller-apply "player-previous-track"))

(defun-splotch-transient splotch-controller-volume-up ()
  "Increase the volume for the active device."
  (interactive)
  (splotch-controller-apply "volume-up"))

(defun-splotch-transient splotch-controller-volume-down ()
  "Increase the volume for the active device."
  (interactive)
  (splotch-controller-apply "volume-down"))

(defun splotch-controller-volume-mute-unmute ()
  "Mute/unmute the volume for the active device."
  (interactive)
  (splotch-controller-apply "volume-mute-unmute"))

(defun splotch-controller-toggle-repeat ()
  "Sends a command to Spotify process to toggle the repeating flag."
  (interactive)
  (splotch-controller-apply "toggle-repeat"))

(defun splotch-controller-toggle-shuffle ()
  "Sends a command to Spotify process to toggle the shuffling flag."
  (interactive)
  (splotch-controller-apply "toggle-shuffle"))

(defun splotch-controller-is-repeating ()
  "Sends a command to Spotify process to get the current repeating state."
  (splotch-controller-apply "is-repeating"))

(defun splotch-controller-is-shuffling ()
  "Sends a command to the Spotify process to get the current shuffling state."
  (splotch-controller-apply "is-shuffling"))

(provide 'splotch-controller)
;;; splotch-controller.el ends here
