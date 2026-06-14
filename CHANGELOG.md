# Changelog

All notable changes in this fork ([`eigen-spaced/smudge`](https://github.com/eigen-spaced/smudge))
relative to upstream [`danielfm/smudge`](https://github.com/danielfm/smudge) are
documented here.

## [Unreleased]

### Fixed — Spotify Web API February 2026 breaking changes

The [February 2026 Web API changes][feb2026] broke search, playlist browsing and
track listing on upstream Smudge. The affected endpoints and response parsing in
`smudge-api.el` were updated:

- **Search** (`smudge-api-search`): the `/search` `limit` maximum dropped from 50
  to 10; capped accordingly. `smudge-api-search-limit` still applies (up to 50) to
  playlist/track pagination, which kept the higher cap.
- **My playlists** (`smudge-api-user-playlists`): `GET /users/{id}/playlists` was
  removed; now uses `GET /me/playlists`.
- **Playlist track count** (`smudge-api-get-playlist-track-count`): the playlist
  `tracks` object was renamed to `items`; also made nil-safe for non-owned
  playlists, which now return metadata only.
- **Playlist tracks** (`smudge-api-playlist-tracks`):
  `GET /users/{owner}/playlists/{id}/tracks` was renamed to
  `GET /playlists/{id}/items` (the owner path segment is gone).
- **Playlist track parsing** (`smudge-api-get-playlist-tracks`): each playlist
  item's `track` field was renamed to `item`.
- **Popularity bar** (`smudge-api-popularity-bar`): the Track `popularity` field
  was removed; the bar now renders empty instead of erroring on a nil value.

### Changed — write paths updated for February 2026 (unverified)

These less-used write paths were moved to the new endpoints. They are not part of
the maintainer's daily workflow, and the request body for the consolidated
library endpoint has **not yet been verified against the live API** (flagged with
a `NOTE:` in-code):

- **Create playlist** (`smudge-api-playlist-create`): `POST /users/{id}/playlists`
  → `POST /me/playlists`.
- **Add tracks to playlist** (`smudge-api-playlist-add-tracks`):
  `POST /users/{id}/playlists/{id}/tracks` → `POST /playlists/{id}/items`
  (request body unchanged: a JSON array of Spotify URIs).
- **Remove tracks from playlist** (`smudge-api-playlist-remove-tracks`):
  `DELETE /playlists/{id}/tracks` → `DELETE /playlists/{id}/items`.
- **Save/remove library tracks** (`smudge-api-save-tracks-to-my-library`,
  `smudge-api-remove-tracks-from-my-library`): the per-type `PUT`/`DELETE`
  `/me/tracks` endpoints were consolidated into `/me/library`, which now takes
  full Spotify URIs rather than bare IDs.

### Added

- **`smudge-apple-return-focus-after-play`** (macOS, defaults to `t`): Spotify's
  AppleScript `play track` command raises the Spotify app to the foreground
  (unlike play/pause, next and previous). When this option is enabled, Smudge
  records whichever app was frontmost, issues the play, then re-activates that
  app — so starting a track from a Smudge buffer keeps you in Emacs. The play is
  issued asynchronously, so Emacs never blocks.

[feb2026]: https://developer.spotify.com/documentation/web-api/references/changes/february-2026
