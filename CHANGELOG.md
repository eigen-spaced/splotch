# Changelog

All notable changes in this fork ([`eigen-spaced/splotch`](https://github.com/eigen-spaced/splotch))
relative to upstream [`danielfm/smudge`](https://github.com/danielfm/smudge) are
documented here.

## [Unreleased]

### Changed — project renamed from Smudge to Splotch

This fork has been renamed from `smudge` to `splotch`, out of respect for the
upstream author and to avoid confusion with the original package. All file names,
command and variable prefixes (`smudge-` → `splotch-`), the customization group,
and the OAuth redirect path (`smudge_api_callback` → `splotch_api_callback`) now
use the `splotch` name.

**Migration for existing users:**

- Update the redirect URI registered in your [Spotify Developer app][app-list] to
  `http://127.0.0.1:8080/splotch_api_callback`.
- Rename any `smudge-*` settings in your config to their `splotch-*` equivalents.

Splotch is maintained as a separate project from upstream Smudge; these changes
are not submitted back upstream, and Splotch is not published to MELPA.

### Fixed — Spotify Web API February 2026 breaking changes

The [February 2026 Web API changes][feb2026] broke search, playlist browsing and
track listing on upstream Smudge. The affected endpoints and response parsing in
`splotch-api.el` were updated:

- **Search** (`splotch-api-search`): the `/search` `limit` maximum dropped from 50
  to 10; capped accordingly. `splotch-api-search-limit` still applies (up to 50) to
  playlist/track pagination, which kept the higher cap.
- **My playlists** (`splotch-api-user-playlists`): `GET /users/{id}/playlists` was
  removed; now uses `GET /me/playlists`.
- **Playlist track count** (`splotch-api-get-playlist-track-count`): the playlist
  `tracks` object was renamed to `items`; also made nil-safe for non-owned
  playlists, which now return metadata only.
- **Playlist tracks** (`splotch-api-playlist-tracks`):
  `GET /users/{owner}/playlists/{id}/tracks` was renamed to
  `GET /playlists/{id}/items` (the owner path segment is gone).
- **Playlist track parsing** (`splotch-api-get-playlist-tracks`): each playlist
  item's `track` field was renamed to `item`.
- **Popularity bar** (`splotch-api-popularity-bar`): the Track `popularity` field
  was removed; the bar now renders empty instead of erroring on a nil value.

### Changed — write paths updated for February 2026 (unverified)

These less-used write paths were moved to the new endpoints. They are not part of
the maintainer's daily workflow, and the request body for the consolidated
library endpoint has **not yet been verified against the live API** (flagged with
a `NOTE:` in-code):

- **Create playlist** (`splotch-api-playlist-create`): `POST /users/{id}/playlists`
  → `POST /me/playlists`.
- **Add tracks to playlist** (`splotch-api-playlist-add-tracks`):
  `POST /users/{id}/playlists/{id}/tracks` → `POST /playlists/{id}/items`
  (request body unchanged: a JSON array of Spotify URIs).
- **Remove tracks from playlist** (`splotch-api-playlist-remove-tracks`):
  `DELETE /playlists/{id}/tracks` → `DELETE /playlists/{id}/items`.
- **Save/remove library tracks** (`splotch-api-save-tracks-to-my-library`,
  `splotch-api-remove-tracks-from-my-library`): the per-type `PUT`/`DELETE`
  `/me/tracks` endpoints were consolidated into `/me/library`, which now takes
  full Spotify URIs rather than bare IDs.

### Added

- **`splotch-apple-return-focus-after-play`** (macOS, defaults to `t`): Spotify's
  AppleScript `play track` command raises the Spotify app to the foreground
  (unlike play/pause, next and previous). When this option is enabled, Splotch
  records whichever app was frontmost, issues the play, then re-activates that
  app — so starting a track from a Splotch buffer keeps you in Emacs. The play is
  issued asynchronously, so Emacs never blocks.
- **`splotch-add-playing-track-to-playlist`**: add the currently playing track to
  one of your playlists, picked with completion. Bound to `a` in the tracks
  submap (`[prefix] t a`). Reuses the playlist picker, so it only offers
  playlists you can modify.
- **"Added" column** in the playlist track view: replaces the now-defunct
  Popularity column with the date each track was added to the playlist
  (`added_at`, formatted `YYYY-MM-DD`). Shown only in playlist views — track
  search and album views, which have no such date, simply drop the column.

### Changed

- **Playlist picker** (`splotch-track-select-playlist`, used by `splotch-track-add`
  and `splotch-add-playing-track-to-playlist`): now offers only playlists you can
  modify (owned or collaborative) instead of every followed playlist — adding to
  a followed playlist is rejected by the API. It also gathers **all** pages of
  your playlists before prompting, rather than only the first ~50.

### Fixed

- A `C-g`/quit during an async prompt (e.g. the playlist picker) no longer prints
  `error in process sentinel: Quit`; the request success callback is wrapped in
  `with-local-quit`, so the quit aborts cleanly and is still honoured once control
  returns to the command loop.
- The playlist picker no longer errors with `stringp, nil` when the selection
  doesn't resolve to a playlist id (e.g. raw input forced past `require-match`);
  it reports "No playlist selected" instead.

[feb2026]: https://developer.spotify.com/documentation/web-api/references/changes/february-2026
[app-list]: https://developer.spotify.com/dashboard
