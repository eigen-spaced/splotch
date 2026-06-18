;;; splotch-api.el --- Splotch API integration layer  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Daniel Martins

;; SPDX-License-Identifier:  GPL-3.0-or-later

;;; Commentary:

;; This library is the interface to the Spotify RESTful API.  It also does some
;; custom handling of the OAuth code exchange via 'simple-httpd

;;; Code:

(require 'simple-httpd)
(require 'request)
(require 'oauth2)
(require 'browse-url)
(require 'plstore)

(defcustom splotch-oauth2-client-id ""
  "The unique identifier for your application.
More info at https://developer.spotify.com/web-api/tutorial/."
  :group 'splotch
  :type 'string)

(defcustom splotch-oauth2-client-secret ""
  "The OAuth2 key provided by Spotify.
This is the key that you will need to pass in secure calls to the Spotify
Accounts and Web API services.  More info at
https://developer.spotify.com/web-api/tutorial/."
  :group 'splotch
  :type 'string)

(defcustom splotch-api-search-limit 50
  "Number of items returned when searching for something using the Spotify API."
  :group 'splotch
  :type 'integer)

(defcustom splotch-api-locale "en_US"
  "Optional.  The desired language.
This consists of an ISO 639 language code and an ISO 3166-1 alpha-2 country
code, joined by an underscore.  Example: es_MX, meaning Spanish (Mexico).
Provide this parameter if you want the category metadata returned in a
 particular language."
  :group 'splotch
  :type 'string)

(defcustom splotch-api-country "US"
  "Optional.  An ISO 3166-1 alpha-2 country code.
Provide this parameter if you want to narrow the list of returned categories
to those to a particular country.  If omitted, the returned items will be
globally relevant."
  :group 'splotch
  :type 'string)

(defcustom splotch-oauth2-callback-scheme "http"
  "The scheme for the httpd to listen on for the OAuth2 callback."
  :group 'splotch
  :type 'string)

(defcustom splotch-oauth2-callback-host "127.0.0.1"
  "The host for the httpd to listen on for the OAuth2 callback."
  :group 'splotch
  :type 'string)

(defcustom splotch-oauth2-callback-port "8080"
  "The port for the httpd to listen on for the OAuth2 callback."
  :group 'splotch
  :type 'string)

(defcustom splotch-oauth2-callback-endpoint "splotch_api_callback"
  "The endpoint for the httpd to listen on for the OAuth2 callback.
Note: This must match the httpd endpoint in `splotch-api-oauth2-request-authorization'."
  :group 'splotch
  :type 'string)

(defvar splotch-user nil
  "Cached user object.")

(defvar splotch-api-oauth2-token nil
  "Cached OAuth2 token.")

(defvar splotch-api-oauth2-auth-code nil
  "Temporary storage for OAuth2 authorization code received from callback.")

(defvar splotch-api-oauth2-callback-state nil
  "Temporary storage for OAuth2 state parameter to validate callback.")

(defvar splotch-api-oauth2-auth-in-progress nil
  "Flag indicating whether OAuth2 authentication is currently in progress.")

(defconst splotch-api-endpoint
  "https://api.spotify.com/v1"
  "Spotify API endpoint.")

(defconst splotch-api-oauth2-auth-url
  "https://accounts.spotify.com/authorize"
  "Spotify API authorization endpoint.")

(defconst splotch-api-oauth2-token-url
  "https://accounts.spotify.com/api/token"
  "Spotify API token endpoint.")

(defconst splotch-api-oauth2-scopes
  (string-join
   '("playlist-read-private"
     "playlist-read-collaborative"
     "playlist-modify-public"
     "playlist-modify-private"
     "user-read-private"
     "user-read-playback-state"
     "user-modify-playback-state"
     "user-read-playback-state"
     "user-read-recently-played"
     "user-library-read"
     "user-library-modify")
   " ")
  "Spotify API scopes required by Splotch.")

(defun splotch-api-oauth2-generate-state ()
  "Generate a random state string for OAuth2 CSRF protection."
  (format "%04x%04x-%04x-%04x-%04x-%04x%04x%04x"
          (random 65536) (random 65536)
          (random 65536)
          (random 65536)
          (random 65536)
          (random 65536) (random 65536) (random 65536)))

(defun splotch-api-oauth2-start-server ()
  "Start the HTTP server for OAuth2 callback.
Uses the port and host configured in `splotch-oauth2-callback-port' and
`splotch-oauth2-callback-host'."
  (let ((port (string-to-number splotch-oauth2-callback-port)))
    (setq httpd-port port)
    (setq httpd-host splotch-oauth2-callback-host)
    (httpd-start)))

(defun splotch-api-oauth2-stop-server ()
  "Stop the HTTP server for OAuth2 callback."
  ;; Kill any remaining httpd connections
  (dolist (proc (process-list))
    (when (and (process-name proc)
               (string-prefix-p "httpd" (process-name proc)))
      (delete-process proc)))
  (httpd-stop))

(defservlet* splotch_api_callback text/html (code state error)
  "Handle OAuth2 callback from Spotify authorization.
Captures the authorization CODE and STATE parameters."
  (cond
   (error
    (insert (format "<html><body><h1>Authorization Error</h1><p>%s</p><p>You can close this window.</p></body></html>" error)))
   ((not (string= state splotch-api-oauth2-callback-state))
    (insert "<html><body><h1>Authorization Error</h1><p>Invalid state parameter.</p><p>You can close this window.</p></body></html>"))
   (t
    (setq splotch-api-oauth2-auth-code code)
    (insert "<html>
<head>
  <title>Authorization Successful</title>
</head>
<body>
  <h1>Authorization Successful!</h1>
  <p>You can return to Emacs.</p>
  <p>This window will close in <span id=\"timer\">5</span> seconds...</p>
  <p><button onclick=\"window.close()\">Close Now</button></p>
  <script>
    let seconds = 5;
    const timerElement = document.getElementById('timer');
    const countdown = setInterval(() => {
      seconds--;
      timerElement.textContent = seconds;
      if (seconds <= 0) {
        clearInterval(countdown);
        window.close();
      }
    }, 1000);
  </script>
</body>
</html>"))))

(defun splotch-api-oauth2-auth (auth-url token-url client-id client-secret &optional scope redirect-uri)
  "Authenticate application via OAuth2.
Send CLIENT-ID and CLIENT-SECRET to AUTH-URL.  Get code and send to TOKEN-URL.
Starts a local HTTP server to capture the authorization code from the callback."
  (let ((inhibit-message t)
        (state (splotch-api-oauth2-generate-state)))
    ;; Set flag to prevent concurrent auth flows
    (setq splotch-api-oauth2-auth-in-progress t)

    ;; Reset auth code from any previous attempt
    (setq splotch-api-oauth2-auth-code nil)
    (setq splotch-api-oauth2-callback-state state)

    ;; Start the HTTP server to listen for the callback
    (splotch-api-oauth2-start-server)

    ;; Build authorization URL and open in browser
    (let ((auth-request-url
           (concat auth-url
                   (if (string-match-p "\\?" auth-url) "&" "?")
                   (url-build-query-string
                    `((client_id ,client-id)
                      (response_type "code")
                      (redirect_uri ,redirect-uri)
                      (scope ,scope)
                      (state ,state))))))
      (browse-url auth-request-url))

    ;; Wait for the authorization code to be received by the callback
    (message "Waiting for authorization callback...")
    (while (not splotch-api-oauth2-auth-code)
      (sleep-for 0.5))

    ;; Exchange the authorization code for an access token using built-in oauth2 function.
    ;; Pass the "splotch" host-name so the token's request-cache is keyed the same way
    ;; `splotch-api-oauth2-token' later refreshes it; otherwise the first refresh after
    ;; auth always misses the cache and makes a needless network round-trip.
    (let ((token (oauth2-request-access
                  auth-url
                  token-url
                  client-id
                  client-secret
                  splotch-api-oauth2-auth-code
                  redirect-uri
                  "splotch")))

      ;; Stop the HTTP server
      (splotch-api-oauth2-stop-server)

      ;; Store the token using built-in plstore function
      (let ((plstore-id (oauth2-compute-id auth-url token-url scope client-id ""))
            (plstore (plstore-open oauth2-token-file)))
        (setf (oauth2-token-plstore-id token) plstore-id)
        (oauth2--update-plstore plstore token)
        (plstore-close plstore))

      ;; Clean up temporary variables
      (setq splotch-api-oauth2-auth-code nil)
      (setq splotch-api-oauth2-callback-state nil)
      (setq splotch-api-oauth2-auth-in-progress nil)

      token)))

(defun splotch-api-oauth2-load-token ()
  "Load OAuth2 token from disk if it exists."
  (let* ((plstore-id (oauth2-compute-id
                      splotch-api-oauth2-auth-url
                      splotch-api-oauth2-token-url
                      splotch-api-oauth2-scopes
                      splotch-oauth2-client-id
                      ""))
         (plstore (plstore-open oauth2-token-file))
         (stored-data (plstore-get plstore plstore-id)))
    (plstore-close plstore)
    (when stored-data
      (let* ((plist (cdr stored-data))
             (token-data (plist-get plist :access-response))
             (access-token (cdr (assoc 'access_token token-data)))
             (refresh-token (cdr (assoc 'refresh_token token-data))))
        (when access-token
          (make-oauth2-token
           :plstore-id plstore-id
           :client-id splotch-oauth2-client-id
           :client-secret splotch-oauth2-client-secret
           :access-token access-token
           :refresh-token refresh-token
           :token-url splotch-api-oauth2-token-url
           :access-response token-data))))))

(defun splotch-api-oauth2-run-auth ()
  "Run the interactive Spotify sign-in flow and return a fresh OAuth2 token.
Used both for the first authorization and to recover after the refresh token
has expired or been revoked (Spotify `invalid_grant')."
  (let ((inhibit-message nil))
    (message "Splotch: Spotify sign-in required — a browser will open to authorize."))
  (splotch-api-oauth2-auth
   splotch-api-oauth2-auth-url
   splotch-api-oauth2-token-url
   splotch-oauth2-client-id
   splotch-oauth2-client-secret
   splotch-api-oauth2-scopes
   (format "%s://%s:%s/%s"
           splotch-oauth2-callback-scheme
           splotch-oauth2-callback-host
           splotch-oauth2-callback-port
           splotch-oauth2-callback-endpoint)))

(defun splotch-api-oauth2-token ()
  "Retrieve the OAuth2 access token used to interact with the Spotify API.
Order of preference: in-memory token, on-disk token, or a fresh sign-in.

`oauth2-refresh-access' reuses the cached access token until it expires, then
mints a new one from the refresh token.  When the refresh token itself has
expired or been revoked, Spotify returns `invalid_grant'; the oauth2 library
then deletes the stored token and returns nil, and we send the user back through
the sign-in flow.  (Spotify refresh tokens expire after six months as of
2026-07-20.)  A transient refresh failure also returns nil but leaves the stored
token on disk intact, so we reload and keep using it rather than forcing a
needless re-login.  Spin and wait if another call is already authenticating."
  (let ((inhibit-message t))
    ;; If auth is already in progress, wait for it to complete.
    (while splotch-api-oauth2-auth-in-progress
      (sleep-for 0.5))

    ;; Prefer an in-memory or on-disk token; otherwise sign in.
    (unless splotch-api-oauth2-token
      (setq splotch-api-oauth2-token
            (or (splotch-api-oauth2-load-token)
                (splotch-api-oauth2-run-auth))))

    ;; Refresh (reuses the cached access token until it expires).  On
    ;; invalid_grant the library deletes the stored token and returns nil.
    (when splotch-api-oauth2-token
      (setq splotch-api-oauth2-token
            (oauth2-refresh-access splotch-api-oauth2-token "splotch")))

    ;; Refresh nulled the token: if the on-disk token is gone, the refresh token
    ;; was rejected (invalid_grant) and we must re-authenticate; if it survived,
    ;; the failure was transient, so reuse it.
    (unless splotch-api-oauth2-token
      (setq splotch-api-oauth2-token
            (or (splotch-api-oauth2-load-token)
                (splotch-api-oauth2-run-auth))))

    splotch-api-oauth2-token))

(defun splotch-api-call-async (method uri &optional data callback)
  "Make a request to the given Spotify service endpoint URI via METHOD.
Call CALLBACK with the parsed JSON response."
  (request (concat splotch-api-endpoint uri)
    :headers `(("Authorization" .
                ,(format "Bearer %s" (oauth2-token-access-token (splotch-api-oauth2-token))))
               ("Accept" . "application/json")
               ("Content-Type" . "application/json")
               ("Content-Length" . ,(number-to-string (length data))))
    :type method
    :parser (lambda ()
              (condition-case nil
                  (json-parse-buffer
                   :object-type 'hash-table
                   :array-type 'list)
                (json-parse-error nil)
                (json-end-of-file nil)))
    :encoding 'utf-8
    :data data
    :success (cl-function
              (lambda (&rest data &key response &allow-other-keys)
                ;; Callbacks may prompt the user (e.g. `completing-read') and run
                ;; inside request's process sentinel; `with-local-quit' keeps a
                ;; C-g there from surfacing as "error in process sentinel: Quit"
                ;; (the quit is still honoured once control returns to the loop).
                (when callback
                  (with-local-quit
                    (funcall callback (request-response-data response))))))

    :error (cl-function
            (lambda (&rest args &key error-thrown &allow-other-keys)
              (message "Got error: %S" error-thrown)))))

(defun splotch-api-current-user (callback)
  "Call CALLBACK with the currently logged in user."
  (if splotch-user
      (funcall callback splotch-user)
    (splotch-api-call-async
     "GET"
     "/me"
     nil
     (lambda (user)
       (setq splotch-user user)
       (funcall callback user)))))

(defun splotch-api-get-items (json)
  "Return the list of items from the given JSON object."
  (gethash "items" json))

(defun splotch-api-get-search-track-items (json)
  "Return track items from the given search results JSON object."
  (splotch-api-get-items (gethash "tracks" json)))

(defun splotch-api-get-search-playlist-items (json)
  "Return playlist items from the given search results JSON object."
  (splotch-api-get-items (gethash "playlists" json)))

(defun splotch-api-get-message (json)
  "Return the message from the featured playlists JSON object."
  (gethash "message" json))

(defun splotch-api-get-playlist-tracks (json)
  "Return the list of tracks from the given playlist JSON object.
Each entry's `added_at' timestamp is copied onto the track object so the track
view can show when the track was added to the playlist."
  ;; Feb-2026: each playlist-items entry's track field was renamed `track' -> `item'.
  (mapcar (lambda (entry)
            (let ((track (gethash "item" entry))
                  (added (gethash "added_at" entry)))
              (when (and (hash-table-p track) added)
                (puthash "added_at" added track))
              track))
          (splotch-api-get-items json)))

(defun splotch-api-get-track-album (json)
  "Return the simplified album object from the given track JSON object."
  (gethash "album" json))

(defun splotch-api-get-track-number (json)
  "Return the track number from the given track JSON object."
  (gethash "track_number" json))

(defun splotch-api-get-disc-number (json)
  "Return the disc number from the given track JSON object."
  (gethash "disc_number" json))

(defun splotch-api-get-track-duration (json)
  "Return the track duration, in milliseconds, from the given track JSON object."
  (gethash "duration_ms" json))

(defun splotch-api-get-track-duration-formatted (json)
  "Return the formatted track duration from the given track JSON object."
  (format-seconds "%m:%02s" (/ (splotch-api-get-track-duration json) 1000)))

(defun splotch-api-get-track-album-name (json)
  "Return the album name from the given track JSON object."
  (splotch-api-get-item-name (splotch-api-get-track-album json)))

(defun splotch-api-get-track-artist (json)
  "Return the first simplified artist object from the given track JSON object."
  (car (gethash "artists" json)))

(defun splotch-api-get-track-artist-name (json)
  "Return the first artist name from the given track JSON object."
  (splotch-api-get-item-name (splotch-api-get-track-artist json)))

(defun splotch-api-get-track-popularity (json)
  "Return the popularity from the given track/album/artist JSON object."
  (gethash "popularity" json))

(defun splotch-api-is-track-playable (json)
  "Return whether the given track JSON object is playable by the current user."
  (not (eq :false (gethash "is_playable" json))))

(defun splotch-api-get-item-name (json)
  "Return the name from the given track/album/artist JSON object."
  (gethash "name" json))

(defun splotch-api-get-item-id (json)
  "Return the id from the given JSON object."
  (gethash "id" json))

(defun splotch-api-get-item-uri (json)
  "Return the uri from the given track/album/artist JSON object."
  (gethash "uri" json))

(defun splotch-api-get-playlist-track-count (json)
  "Return the number of tracks of the given playlist JSON object."
  ;; Feb-2026: playlist `tracks' object renamed -> `items'.  Non-owned playlists
  ;; now return metadata only (no items object), so guard against nil.
  (let ((items (gethash "items" json)))
    (if (hash-table-p items) (or (gethash "total" items) 0) 0)))

(defun splotch-api-get-playlist-owner-id (json)
  "Return the owner id of the given playlist JSON object."
  (splotch-api-get-item-id (gethash "owner" json)))

(defun splotch-api-search (type query page callback)
  "Search artists, albums, tracks or playlists.
Call CALLBACK with PAGE of items that match QUERY, depending on TYPE."
  ;; Feb-2026: the /search `limit' maximum dropped from 50 to 10.  Cap it here;
  ;; `splotch-api-search-limit' stays larger for playlist/track pagination (which
  ;; still allows up to 50 per page).
  (let* ((limit (min splotch-api-search-limit 10))
         (offset (* limit (1- page))))
    (splotch-api-call-async
     "GET"
     (concat "/search?"
             (url-build-query-string `((q      ,query)
                                       (type   ,type)
                                       (limit  ,limit)
                                       (offset ,offset)
                                       (market from_token))
                                     nil t))
     nil
     callback)))

(defun splotch-api-user-playlists (_user-id page callback)
  "Call CALLBACK with the PAGE of playlists for the current user.
USER-ID is ignored: Feb-2026 removed GET /users/{id}/playlists, so we use
GET /me/playlists (the current user's playlists) instead."
  (let ((offset (* splotch-api-search-limit (1- page))))
    (splotch-api-call-async
     "GET"
     (concat "/me/playlists?"
             (url-build-query-string `((limit  ,splotch-api-search-limit)
                                       (offset ,offset))
                                     nil t))
     nil
     callback)))

(defun splotch-api-playlist-create (_user-id name public callback)
  "Create a new playlist with NAME for the current user.
Make PUBLIC if true.  Call CALLBACK with results.
USER-ID is ignored: Feb-2026 removed POST /users/{id}/playlists, so we use
POST /me/playlists (creates under the current user) instead."
  (splotch-api-call-async
   "POST"
   "/me/playlists"
   (format "{\"name\":\"%s\",\"public\":%s}" name (if public "true" "false"))
   callback))

(defun splotch-api-playlist-add-track (user-id playlist-id track-id callback)
  "Add TRACK-ID to PLAYLIST-ID.
Added by USER-ID.  Call CALLBACK with results."
  (splotch-api-playlist-add-tracks user-id playlist-id (list track-id) callback))

(defun splotch-api-format-id (type id)
  "Format ID.  Wrap with TYPE if necessary."
  (if (string-match-p "spotify" id)
      (format "\"%s\"" id)
    (format "\"spotify:%s:%s\"" type id)))

(defun splotch-api-playlist-add-tracks (_user-id playlist-id track-ids callback)
  "Add TRACK-IDs to PLAYLIST-ID.
Call CALLBACK with results.  USER-ID is ignored: Feb-2026 renamed
POST /users/{id}/playlists/{id}/tracks -> POST /playlists/{id}/items
\(the body is unchanged: a JSON array of Spotify URIs)."
  (let ((tracks (format "%s" (mapconcat (lambda (x) (splotch-api-format-id "track" x)) track-ids ","))))
    (splotch-api-call-async
     "POST"
     (format "/playlists/%s/items" (url-hexify-string playlist-id))
     (format "{\"uris\": [ %s ]}" tracks)
     callback)))

(defun splotch-api-playlist-remove-track (playlist-id track-id callback)
  "Remove TRACK-ID from PLAYLIST-ID.
Removed by USER-ID. Call CALLBACK with results."
  (splotch-api-playlist-remove-tracks playlist-id (list track-id) callback))

(defun splotch-api-playlist-remove-tracks (playlist-id track-ids callback)
  "Remove TRACK-IDS from PLAYLIST-ID.
Call CALLBACK with results.  Feb-2026 renamed the path
DELETE /playlists/{id}/tracks -> DELETE /playlists/{id}/items, and renamed the
request body's array field `tracks' -> `items' (of {\"uri\": ...} objects)."
  (let ((tracks (format "%s" (mapconcat
                              (lambda (x) (format "{\"uri\": %s}" (splotch-api-format-id "track" x)))
                              track-ids ","))))
    (splotch-api-call-async
     "DELETE"
     (format "/playlists/%s/items" (url-hexify-string playlist-id))
     (format "{\"items\": [ %s ]}" tracks)
     callback)))

(defun splotch-api-playlist-follow (playlist callback)
  "Add the current user as a follower of PLAYLIST.
Call CALLBACK with results."
  (let ((owner (splotch-api-get-playlist-owner-id playlist))
        (id (splotch-api-get-item-id playlist)))
    (splotch-api-call-async
     "PUT"
     (format "/users/%s/playlists/%s/followers"
             (url-hexify-string owner)
             (url-hexify-string id))
     nil
     callback)))

(defun splotch-api-playlist-unfollow (playlist callback)
  "Remove the current user as a follower of PLAYLIST.
Call CALLBACK with results."
  (let ((owner (splotch-api-get-playlist-owner-id playlist))
        (id (splotch-api-get-item-id playlist)))
    (splotch-api-call-async
     "DELETE"
     (format "/users/%s/playlists/%s/followers"
             (url-hexify-string owner)
             (url-hexify-string id))
     nil
     callback)))

(defun splotch-api-playlist-tracks (playlist page callback)
  "Call CALLBACK with PAGE of results of tracks from PLAYLIST."
  ;; Feb-2026: GET /users/{owner}/playlists/{id}/tracks was renamed to
  ;; GET /playlists/{id}/items (the owner path segment is gone).
  (let ((id (splotch-api-get-item-id playlist))
        (offset (* splotch-api-search-limit (1- page))))
    (splotch-api-call-async
     "GET"
     (concat (format "/playlists/%s/items?" (url-hexify-string id))
             (url-build-query-string `((limit  ,splotch-api-search-limit)
                                       (offset ,offset)
                                       (market from_token))
                                     nil t))
     nil
     callback)))

(defun splotch-api-album-tracks (album page callback)
  "Call CALLBACK with PAGE of tracks for ALBUM."
  (let ((album-id (splotch-api-get-item-id album))
        (offset (* splotch-api-search-limit (1- page))))
    (splotch-api-call-async
     "GET"
     (concat (format "/albums/%s/tracks?"
                     (url-hexify-string album-id))
             (url-build-query-string `((limit ,splotch-api-search-limit)
                                       (offset ,offset)
                                       (market from_token))
                                     nil t))
     nil
     callback)))

(defun splotch-api-popularity-bar (popularity)
  "Return the popularity indicator bar proportional to POPULARITY.
Parameter should be a number between 0 and 100.
Feb-2026 removed Track `popularity', so POPULARITY may be nil; render an empty
bar in that case rather than erroring."
  (let ((num-bars (if (numberp popularity) (truncate (/ popularity 10)) 0)))
    (concat (make-string num-bars ?X)
            (make-string (- 10 num-bars) ?-))))

(defun splotch-api-recently-played (page callback)
  "Call CALLBACK with PAGE of recently played tracks."
  (let ((offset (* splotch-api-search-limit (1- page))))
    (splotch-api-call-async
     "GET"
     (concat "/me/player/recently-played?"
             (url-build-query-string `((limit  ,splotch-api-search-limit)
                                       (offset ,offset))
                                     nil t))
     nil
     callback)))

(defun splotch-api-device-list (callback)
  "Call CALLBACK with the list of devices available for use with Spotify Connect."
  (splotch-api-call-async
   "GET"
   "/me/player/devices"
   nil
   callback))

(defun splotch-api-transfer-player (device-id &optional callback)
  "Transfer playback to DEVICE-ID and determine if it should start playing.
Call CALLBACK with result if provided."
  (splotch-api-call-async
   "PUT"
   "/me/player"
   (format "{\"device_ids\":[\"%s\"]}" device-id)
   callback))

(defun splotch-api-set-volume (device-id percentage &optional callback)
  "Set the volume level to PERCENTAGE of max for DEVICE-ID."
  (splotch-api-call-async
   "PUT"
   (concat "/me/player/volume?"
           (url-build-query-string `((volume_percent ,percentage)
                                     (device_id      ,device-id))
                                   nil t))
   nil
   callback))

(defun splotch-api-get-player-status (callback)
  "Call CALLBACK with the Spotify Connect status of the currently active player."
  (splotch-api-call-async
   "GET"
   "/me/player"
   nil
   callback))

(defun splotch-api-play (&optional callback uri context)
  "Play a track.  If no args, resume playing current track.
Otherwise, play URI in CONTEXT.  Call CALLBACK with results if provided."
  (splotch-api-call-async
   "PUT"
   "/me/player/play"
   (concat " { "
           (cond ((and uri context) (format "\"context_uri\": \"%s\", \"offset\": {\"uri\": \"%s\"}" context uri))
                 (context           (format "\"context_uri\": \"%s\"" context))
                 (uri               (format "\"uris\": [ \"%s\" ]" uri))
                 (t                  ""))
           " } ")
   callback))

(defun splotch-api-pause (&optional callback)
  "Pause the currently playing track.
Call CALLBACK if provided."
  (splotch-api-call-async
   "PUT"
   "/me/player/pause"
   nil
   callback))

(defun splotch-api-next (&optional callback)
  "Skip to the next track.
Call CALLBACK if provided."
  (splotch-api-call-async
   "POST"
   "/me/player/next"
   nil
   callback))

(defun splotch-api-previous (&optional callback)
  "Skip to the previous track.
Call CALLBACK if provided."
  (splotch-api-call-async
   "POST"
   "/me/player/previous"
   nil
   callback))

(defun splotch-api-repeat (state &optional callback)
  "Set repeat of current track to STATE.
Call CALLBACK if provided."
  (splotch-api-call-async
   "PUT"
   (concat "/me/player/repeat?"
           (url-build-query-string `((state ,state))
                                   nil t))
   nil
   callback))

(defun splotch-api-shuffle (state &optional callback)
  "Set repeat of current track to STATE.
Call CALLBACK if provided."
  (splotch-api-call-async
   "PUT"
   (concat "/me/player/shuffle?"
           (url-build-query-string `((state ,state))
                                   nil t))
   nil
   callback))


(defun splotch-api-queue-add-track (track-id &optional callback)
  "Add given TRACK-ID to the queue and call CALLBACK afterwards."
  (splotch-api-call-async
   "POST"
   (concat "/me/player/queue?"
           (url-build-query-string `((uri ,track-id))
                                   nil t))
   nil
   callback))

(defun splotch-api-queue-add-tracks (track-ids &optional callback)
  "Add given TRACK-IDS to the queue and call CALLBACK afterwards."
  ;; Spotify's API doesn't provide a endpoint that would enable us to
  ;; add multiple tracks to the queue at the same time.
  ;; Thus we have to synchronously add the tracks
  ;; one by one to the queue.
  (if (car track-ids)
      (splotch-api-queue-add-track
       (car track-ids)
       (lambda (_)
         (splotch-api-queue-add-tracks (cdr track-ids) callback)))
    (when callback (funcall callback))))

(defun splotch-api-save-tracks-to-my-library (track-ids &optional callback)
  "Save one or more TRACK-IDS to the user's \"Liked Songs\" library.

Up to 50 tracks can be specified per API call.

Calls CALLBACK function with the API response.

Feb-2026 consolidated the per-type PUT /me/{tracks,albums,...} endpoints into
PUT /me/library, which takes full Spotify URIs (not bare IDs).  The {\"uris\": [...]}
body is verified against the live Web API reference."
  (splotch-api-call-async
   "PUT"
   "/me/library"
   (format "{\"uris\": [ %s ]}"
           (mapconcat (lambda (id) (splotch-api-format-id "track" id)) track-ids ","))
   callback))

(defun splotch-api-remove-tracks-from-my-library (track-ids &optional callback)
  "Remove one or more TRACK-IDS from the user's \"Liked Songs\" library.

Up to 50 tracks can be specified per API call.

Calls CALLBACK function with the API response.

Feb-2026 consolidated the per-type DELETE /me/{tracks,albums,...} endpoints into
DELETE /me/library, which takes full Spotify URIs (not bare IDs).  The {\"uris\": [...]}
body is verified against the live Web API reference."
  (splotch-api-call-async
   "DELETE"
   "/me/library"
   (format "{\"uris\": [ %s ]}"
           (mapconcat (lambda (id) (splotch-api-format-id "track" id)) track-ids ","))
   callback))

(defun splotch-api-get-my-library-tracks (page callback)
  "Get PAGE of songs saved in the user's \"Liked Songs\"library.

Calls CALLBACK function with the API response."
  (let ((offset (* splotch-api-search-limit (1- page))))
    (splotch-api-call-async
     "GET"
     (concat "/me/tracks?"
             (url-build-query-string `((limit ,splotch-api-search-limit)
                                       (offset ,offset)
                                       (market from_token))))
     nil
     callback)))

(provide 'splotch-api)
;;; splotch-api.el ends here
