;;; splotch-apple.el --- Apple-specific code for Splotch  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library handles controlling Spotify via Applescript commands. It
;; implements a set of multimethod-like functions that are dispatched in
;; splotch-controller.el.

;;; Code:

(require 'splotch-controller)

(defcustom splotch-osascript-bin-path "/usr/bin/osascript"
  "Path to `osascript' binary."
  :group 'splotch
  :type 'string)

(defcustom splotch-apple-return-focus-after-play t
  "When non-nil, restore window focus after starting a track.
Spotify's AppleScript `play track' command raises the Spotify app to the
foreground (unlike playpause/next/previous, which don't), so starting a track
from a Splotch buffer yanks you out of Emacs.  With this enabled, Splotch records
whichever app was frontmost, issues the play, then re-activates that app — so
playback stays distraction-free.  macOS only."
  :group 'splotch
  :type 'boolean)

;; Do not change this unless you know what you're doing
(defconst splotch-apple-player-status-script "
# Source: https://github.com/andrehaveman/smudge-node-applescript
on escape_quotes(string_to_escape)
  set AppleScript's text item delimiters to the \"\\\"\"
  set the item_list to every text item of string_to_escape
  set AppleScript's text item delimiters to the \"\\\\\\\"\"
  set string_to_escape to the item_list as string
  set AppleScript's text item delimiters to \"\"
  return string_to_escape
end escape_quotes

tell application \"Spotify\"
  if it is running then
    set ctrack to \"{\"
    set ctrack to ctrack & \"\\\"artist\\\": \\\"\" & my escape_quotes(current track's artist) & \"\\\"\"
    set ctrack to ctrack & \",\\\"duration\\\": \" & current track's duration
    set ctrack to ctrack & \",\\\"track_number\\\": \" & current track's track number
    set ctrack to ctrack & \",\\\"name\\\": \\\"\" & my escape_quotes(current track's name) & \"\\\"\"
    set ctrack to ctrack & \",\\\"player_state\\\": \\\"\" & player state & \"\\\"\"
    set ctrack to ctrack & \",\\\"player_shuffling\\\": \" & shuffling
    set ctrack to ctrack & \",\\\"player_repeating\\\": \" & repeating
    set ctrack to ctrack & \"}\"
  end if
end tell
")

;; Write script to a temp file
(defconst splotch-apple-player-status-script-file
  (make-temp-file "splotch.el" nil nil splotch-apple-player-status-script))

(defun splotch-apple-command-line (cmd)
  "Return a command line prefix for any Spotify command CMD."
  (format "%s -e %s"
          splotch-osascript-bin-path
          (shell-quote-argument (format "tell application \"Spotify\" to %s" cmd))))

(defun splotch-apple-command (cmd)
  "Send the given CMD to the Spotify client.
Return the resulting status string."
  (replace-regexp-in-string
   "\n$" ""
   (shell-command-to-string (splotch-apple-command-line cmd))))

(defun splotch-apple-set-player-status-from-process-output (process output)
  "Set the OUTPUT of the player status PROCESS to the player status."
  (splotch-controller-update-metadata output)
  (with-current-buffer (process-buffer process)
    (delete-region (point-min) (point-max))))

(defun splotch-apple-player-status ()
  "Update the player status to display the current Spotify player status."
  (let* ((process-name "splotch-player-status")
         (process-status (process-status process-name))
         (cmd (format "%s %s" splotch-osascript-bin-path splotch-apple-player-status-script-file)))
    (unless process-status
      (let* ((default-directory user-emacs-directory)
             (process (start-process-shell-command process-name "*splotch-player-status*" cmd)))
        (set-process-filter process 'splotch-apple-set-player-status-from-process-output)))))

(defun splotch-apple-player-state ()
  "Dispatch get player state."
  (splotch-apple-command "get player state"))

(defun splotch-apple-player-toggle-play ()
  "Dispatch playpause."
  (splotch-apple-command "playpause"))

(defun splotch-apple-player-next-track ()
  "Dispatch next track."
  (splotch-apple-command "next track"))

(defun splotch-apple-player-previous-track ()
  "Dispatch previous track."
  (splotch-apple-command "previous track"))

(defun splotch-apple-volume-up ()
  "Send message about inability to change volume."
  (message "Changing the volume not supported by the Spotify AppleScript client"))

(defun splotch-apple-volume-down ()
  "Send message about inability to change volume."
  (message "Changing the volume not supported by the Spotify AppleScript client"))

(defun splotch-apple-volume-mute-unmute ()
  "Send message about inability to change volume."
  (message "Changing the volume not supported by the Spotify AppleScript client"))

(defun splotch-apple-toggle-repeat ()
  "Dispatch repeat command."
  (splotch-apple-command "set repeating to not repeating"))

(defun splotch-apple-toggle-shuffle ()
  "Dispatch shuffle command."
  (splotch-apple-command "set shuffling to not shuffling"))

(defun splotch-apple-player-play-track (track-id context-id)
  "Dispatch message about playing TRACK-ID in CONTEXT-ID.
When `splotch-apple-return-focus-after-play' is non-nil, capture the frontmost
app, play, and re-activate it so Spotify doesn't steal focus.  Done in a single
asynchronous osascript so Emacs never blocks and the ordering is deterministic."
  (if splotch-apple-return-focus-after-play
      (let ((script
             (format (concat
                      "tell application \"System Events\" to"
                      " set frontApp to name of first process whose frontmost is true\n"
                      "tell application \"Spotify\" to play track \"%s\" in context \"%s\"\n"
                      "delay 0.1\n"
                      "tell application frontApp to activate")
                     track-id context-id)))
        (start-process "splotch-play" nil splotch-osascript-bin-path "-e" script))
    (splotch-apple-command (format "play track \"%s\" in context \"%s\"" track-id context-id))))

(provide 'splotch-apple)
;;; splotch-apple.el ends here
