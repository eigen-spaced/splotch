# Splotch

**Control Spotify app from within Emacs.**

[![asciicast](https://asciinema.org/a/218654.svg)](https://asciinema.org/a/218654)

Splotch allows you to control the Spotify application from within your favorite text
editor. If you are running on Mac OS X or Linux, you can control the locally running instance. If
you are running on any platform with a network connection (including Windows - and even headless!)
and have a Spotify premium subscription, you can control an instance of Spotify via the Spotify
Connect feature.

> **Note — Splotch is a fork of Smudge.** [`eigen-spaced/splotch`](https://github.com/eigen-spaced/splotch)
> is an independently maintained fork of [`danielfm/smudge`](https://github.com/danielfm/smudge).
> Huge thanks to [Daniel Martins (`danielfm`)](https://github.com/danielfm) and the Smudge
> contributors — Splotch is built entirely on their work.
>
> This fork is a more up-to-date version: it adds fixes for the **Spotify Web API February 2026
> breaking changes** (which broke search, playlist browsing and track listing on upstream) plus a
> macOS focus option (see [Keeping Focus After Starting a Track](#macos-keeping-focus-after-starting-a-track)),
> so it currently runs ahead of upstream Smudge. The full list of changes is in
> [CHANGELOG.md](./CHANGELOG.md).
>
> These changes are **not** being submitted back upstream — Splotch is maintained as a separate
> project, not a staging ground for Smudge. It is **not published to MELPA**; install it from
> GitHub (see [Installation](#installation)).

## Features

* Spotify client integration for GNU/Linux (via D-Bus) and OS X (via AppleScript)
* Device playback display & selection using the Spotify Connect API (requires premium)
* Communicates with the Spotify API via Oauth2
* Displays the current track in mode line or title bar
* Fetch lyrics for the current track via LRCLIB
* Create playlists (public or private)
* Browse your own playlists, and their tracks
* Search for tracks and playlists that match the given keywords
* Easily control basic Spotify player features like, play/pause, previous,
  next, shuffle, and repeat with the Splotch Remote minor mode

## Installation

Splotch requires Emacs 27.1+.

### Vanilla Emacs

`package.el` is the built-in package manager in Emacs.

Splotch is **not published to MELPA**. On Emacs 29+ you can install it directly from GitHub:

<kbd>M-x</kbd> package-vc-install <kbd>[RET]</kbd> https://github.com/eigen-spaced/splotch <kbd>[RET]</kbd>

Or put the following snippet into your Emacs configuration:

```elisp
(use-package! splotch
  :bind-keymap ("C-c ." . splotch-command-map)
  :custom
  (splotch-oauth2-client-secret "...")
  (splotch-oauth2-client-id "...")
  ;; optional: enable transient map for frequent commands
  (splotch-player-use-transient-map t)
  :config
  ;; optional: display current song in mode line
  (global-splotch-remote-mode))
```

### Doom Emacs

Add the following to the `packages.el` file:

```elisp
;; Fetch from GitHub (Splotch is not on MELPA)
(package! splotch
  :recipe (:host github :repo "eigen-spaced/splotch"))
```

Add the following to the `config.el` file:

``` elisp
(use-package! splotch
  :bind-keymap ("C-c ." . splotch-command-map)
  :custom
  (splotch-oauth2-client-secret "...")
  (splotch-oauth2-client-id "...")
  ;; optional: enable transient map for frequent commands
  (splotch-player-use-transient-map t)
  :config
  ;; optional: display current song in mode line
  (global-splotch-remote-mode))
```

## Configuration

```elisp
(setq splotch-oauth2-client-secret "<spotify-app-client-secret>")
(setq splotch-oauth2-client-id "<spotify-app-client-id>")
```

In order to get the client ID and client secret, you need to create a
[Spotify app][app-list], specifying <http://127.0.0.1:8080/splotch_api_callback>
as the redirect URI (or whichever port you have specified via customize). The
OAuth2 exchange is handled by `simple-httpd`. If you are not already using
this package for something else, you should not need to customize this port.
Otherwise, you'll want to set it to whatever port you are running on.

To use the "Spotify Connect" transport (vs. controlling only your local
instance - though you can also control your local instance as well), set
`splotch-transport` to `'connect` as follows. **This feature requires a Spotify
premium subscription.**

```elisp
(setq splotch-transport 'connect)
```

### Key Bindings

``` elisp
; Set C-c . as the Splotch [prefix]
(define-key splotch-mode-map (kbd "C-c .") 'splotch-command-map)
```

The keymap prefix <kbd>C-c .</kbd> is just a suggestion, following the
conventions suggested for minor modes as defined in the Emacs manual
[Key Binding Conventions][kbd-conv]. Previous versions of this package used
<kbd>M-p</kbd>.

The default bindings provided by the `splotch-command-map` is as follows:

| Key                     | Function                                   | Description                                      |
|:------------------------|:-------------------------------------------|:-------------------------------------------------|
| <kbd>[prefix] d</kbd>   | `splotch-select-device`                     | Select a playback device [2]                     |
| <kbd>[prefix] SPC</kbd> | `splotch-controller-toggle-play`            | Play/pause                                       |
| <kbd>[prefix] s</kbd>   | `splotch-controller-toggle-shuffle`         | Turn shuffle on/off [1]                          |
| <kbd>[prefix] r</kbd>   | `splotch-controller-toggle-repeat`          | Turn repeat on/off [1]                           |
| <kbd>[prefix] n</kbd>   | `splotch-controller-next-track`             | Next track                                       |
| <kbd>[prefix] b</kbd>   | `splotch-controller-previous-track`         | Previous track                                   |
| <kbd>[prefix] l</kbd>   | `splotch-lyrics-popup`                       | Show lyrics for the current track                |
| <kbd>[prefix] v u</kbd> | `splotch-controller-volume-up`              | Increase the volume [2]                          |
| <kbd>[prefix] v d</kbd> | `splotch-controller-volume-down`            | Decrease the volume [2]                          |
| <kbd>[prefix] v m</kbd> | `splotch-controller-volume-mute-unmute`     | Alternate the volume between 0 and 100 [2]       |
| <kbd>[prefix] p m</kbd> | `splotch-my-playlists`                      | Show your playlists                              |
| <kbd>[prefix] p s</kbd> | `splotch-playlist-search`                   | Search for playlists                             |
| <kbd>[prefix] p u</kbd> | `splotch-user-playlists`                    | Show playlists for the given user                |
| <kbd>[prefix] p c</kbd> | `splotch-create-playlist`                   | Create a new playlist                            |
| <kbd>[prefix] t s</kbd> | `splotch-track-search`                      | Search for tracks                                |
| <kbd>[prefix] t r</kbd> | `splotch-recently-played`                   | List of recently played tracks                   |
| <kbd>[prefix] t l</kbd> | `splotch-save-playing-track-to-library`     | Save currently playing track to your Library     |
| <kbd>[prefix] t k</kbd> | `splotch-remove-playing-track-from-library` | Remove currently playing track from your Library |

[1] No proper support for this in D-Bus implementation for GNU/Linux
[2] This feature uses Spotify Connect and requires a premium subscription

Splotch can fetch lyrics for the current track using LRCLIB with
`splotch-lyrics-popup` (bound to `[prefix] l` by default). Set
`splotch-lyrics-auto-popup` to non-nil to fetch lyrics on track changes. Note
that auto-updates rely on the periodic player-status refresh (for example,
`global-splotch-remote-mode`), so enable that if you want lyrics to refresh
when tracks advance on their own.

Users of the package hydra may find the code below more convenient for managing
Spotify, _although this isn't officially supported:_

```elisp
;; A hydra for controlling spotify.
(defhydra hydra-spotify (:hint nil)
"
^Search^                  ^Control^               ^Manage^
^^^^^^^^-----------------------------------------------------------------
_t_: Track               _SPC_: Play/Pause        _+_: Volume up
_m_: My Playlists        _n_  : Next Track        _-_: Volume down
_u_: User Playlists      _r_  : Repeat            _d_: Device
^^                       _s_  : Shuffle           _q_: Quit
"
    ("t" splotch-track-search :exit t)
    ("m" splotch-my-playlists :exit t)
    ("u" splotch-user-playlists :exit t)
    ("SPC" splotch-controller-toggle-play :exit nil)
    ("n" splotch-controller-next-track :exit nil)
    ("p" splotch-controller-previous-track :exit nil)
    ("r" splotch-controller-toggle-repeat :exit nil)
    ("s" splotch-controller-toggle-shuffle :exit nil)
    ("+" splotch-controller-volume-up :exit nil)
    ("-" splotch-controller-volume-down :exit nil)
    ("x" splotch-controller-volume-mute-unmute :exit nil)
    ("d" splotch-select-device :exit nil)
    ("q" quit-window "quit" :color blue))

(bind-key "a" #'hydra-spotify/body some-map)
```

A transient map can be enabled to allow repeating frequent commands
(defined in `splotch-transient-command-map`) without having to repeat the
prefix key for `splotch-command-map`.

```elisp
(setq splotch-player-use-transient-map t)
```

### Creating The Spotify App

Go to [Create an Application][app-create] and give your application a name and
a description:

![Creating a Spotify App 1/3](./img/spotify-app-01.png)

After creating the new app, click the **Edit Settings**, scroll down a little bit,
type <http://127.0.0.1:8080/splotch_api_callback> as the Redirect URI for the
application, and click **Add**. Then, hit **Save**.

**IMPORTANT**: After recent changes you must make sure the Redirect URI has underscores '_' and not hyphens '-'!

![Creating a Spotify App 2/3](./img/spotify-app-02.png)

At this point, the client ID and the client secret are available, so set those values to
`splotch-oauth2-client-id` and `splotch-oauth2-client-secret`, respectively.

![Creating a Spotify App 3/3](./img/spotify-app-03.png)

## Usage

### Remote Minor Mode

To display the currently song in the mode line, you can enable the
`global-splotch-remote-mode`. The interval in which the player status is updated
can be configured via the `splotch-player-status-refresh-interval` variable:

```elisp
;; Updates the player status every 10 seconds (default is 5)
;; Note: Set 0 to disable this feature, and avoid values between 1 and 4 when
;; using the 'connect transport.
(setq splotch-player-status-refresh-interval 10)
```
#### Customizing The Player Status

The information displayed in the player status can be customized by setting the
desired format in `splotch-player-status-format`. The following placeholders
are supported:

| Symbol | Description                | Example                        |
|:------:|:---------------------------|:-------------------------------|
|  `%u`  | Track URI                  | `spotify:track:<id>`           |
|  `%a`  | Artist name (truncated)    | `Pink Floyd`                   |
|  `%t`  | Track name (truncated)     | `Us and Them`                  |
|  `%n`  | Track #                    | `7`                            |
|  `%l`  | Track duration, in minutes | `7:49`                         |
|  `%r`  | Player repeat status       | `R`, `-`                       |
|  `%s`  | Player shuffle status      | `S`, `-`                       |
|  `%p`  | Player playing status      | `Playing`, `Paused`, `Stopped` |

The default format is `"[%p: %a - %t ◷ %l %r%s]"`.

The number of characters to be shown in truncated fields can be configured via
the `splotch-player-status-truncate-length` variable.

```elisp
(setq splotch-player-status-truncate-length 10) ; default: 15
```

The text indicator for each of the following player statuses can be configured
via their corresponding variables:

| Player State  | Variable                                  | Default Value |
|:--------------|:------------------------------------------|:-------------:|
| Playing       | `splotch-player-status-playing-text`       |  `"Playing"`  |
| Paused        | `splotch-player-status-paused-text`        |  `"Paused"`   |
| Stopped       | `splotch-player-status-stopped-text`       |  `"Stopped"`  |
| Repeating On  | `splotch-player-status-repeating-text`     |     `"R"`     |
| Repeating Off | `splotch-player-status-not-repeating-text` |     `"-"`     |
| Shuffling On  | `splotch-player-status-shuffling-text`     |     `"S"`     |
| Shuffling Off | `splotch-player-status-not-shuffling-text` |     `"-"`     |

#### Global Remote Mode

This mode can be enabled globally by running
<kbd>M-x global-splotch-remote-mode</kbd>.

### Searching For Tracks

To search for tracks, run <kbd>M-x splotch-track-search</kbd> and type in your
query. The results will be displayed in a separate buffer with the following
key bindings:

| Key              | Description                                                        |
|:-----------------|:-------------------------------------------------------------------|
| <kbd>a</kbd>     | Adds track to a playlist                                           |
| <kbd>l</kbd>     | Loads the next page of results (pagination)                        |
| <kbd>g</kbd>     | Clears the results and reloads the first page of results           |
| <kbd>k</kbd>     | Adds track(s) under the cursor (or inside the region) to the queue |
| <kbd>M-RET</kbd> | Plays the track under the cursor in the context of its album [1]   |

[1] D-Bus implementation for GNU/Linux do not support passing the context, so
only the track under the cursor will be played

The resulting buffer loads the `global-splotch-remote-mode` by default.

**Tip:** In order to customize the number of items fetched per page, just change
the variable `splotch-api-search-limit`:

```elisp
;; Do not use values larger than 50 for better compatibility across endpoints
(setq splotch-api-search-limit 50)
```

### Playing a Spotify URI

To ask Splotch to play a resource by URI, run
<kbd>M-x splotch-play-uri</kbd> and enter the resource URI.

### Creating Playlists

To create new playlists, run <kbd>M-x splotch-create-playlist</kbd> and follow
the prompts.

Currently it's not possible to add tracks to a playlist you own, or to remove
tracks from them.

### Searching For Playlists

To return the playlists for the current user, run
<kbd>M-x splotch-my-playlists</kbd>, or
<kbd>M-x splotch-user-playlists</kbd> to list the public playlists for some
given user. To search playlists that match the given search criteria, run
<kbd>M-x splotch-playlist-search CRITERIA</kbd>. Also, run

All these commands will display results in a separate buffer with the following
key bindings:

| Key              | Description                                              |
|:-----------------|:---------------------------------------------------------|
| <kbd>l</kbd>     | Loads the next page of results (pagination)              |
| <kbd>g</kbd>     | Clears the results and reloads the first page of results |
| <kbd>f</kbd>     | Follows the playlist under the cursor                    |
| <kbd>u</kbd>     | Unfollows the playlist under the cursor                  |
| <kbd>t</kbd>     | Lists the tracks of the playlist under the cursor        |
| <kbd>M-RET</kbd> | Plays the playlist under the cursor                      |

Once you open the list of tracks of a playlist, you get the following key
bindings in the resulting buffer:

| Key              | Description                                                         |
|:-----------------|:--------------------------------------------------------------------|
| <kbd>a</kbd>     | Adds track to a playlist                                            |
| <kbd>r</kbd>     | Removes track from current playlist                                 |
| <kbd>l</kbd>     | Loads the next page of results (pagination)                         |
| <kbd>g</kbd>     | Clears the results and reloads the first page of results            |
| <kbd>f</kbd>     | Follows the current playlist                                        |
| <kbd>u</kbd>     | Unfollows the current playlist                                      |
| <kbd>k</kbd>     | Adds track(s) under the cursor (or inside the region) to the queue  |
| <kbd>M-RET</kbd> | Plays the track under the cursor in the context of the playlist [1] |

Both buffers load the `global-splotch-remote-mode` by default.

[1] D-Bus implementation for GNU/Linux do not support passing the context, so
only the track under the cursor will be played

## Selecting a Device for Playback

<kbd>M-x splotch-select-device</kbd> will display a list of devices available for playback in a separate buffer.

Note: use of this feature requires a Spotify premium subscription.

Once you open the list of devices, you get the following key bindings in the resulting buffer:

| Key            | Description                                       |
|:---------------|:--------------------------------------------------|
| <kbd>RET</kbd> | Transfer playback to the device under the cursor. |
| <kbd>g</kbd>   | Reloads the list of devices                       |

## Specifying the Player Status Location

By default, the player status (playing, paused, track name, time, shuffle, repeat, etc.) are shown
in the modeline. If you want to display the status in the title bar when using a graphical display,
you can set the following:

```elisp
(setq splotch-status-location 'title-bar)
```

Valid values include `'title-bar`, `'modeline` and `nil`, where nil turns off the display of the
player status completely. If the value is set to `title-bar` but you are not using a graphical
display, the player status will be displayed in the mode line instead.

If you want to customize the separator between the existing title bar text and the player status,
you can set the following, i.e.:

```elisp
(setq splotch-title-bar-separator "----")
```

Otherwise, it defaults to 4 spaces.

## macOS: Keeping Focus After Starting a Track

When controlling the local Spotify app on macOS (the default AppleScript
transport), Spotify's `play track` command raises the Spotify app to the
foreground — so starting a track from a Splotch buffer pulls you out of Emacs.
(Play/pause, next and previous don't have this effect.)

By default, Splotch records whichever app was frontmost, issues the play, then
re-activates that app, so playback stays distraction-free. The play is run
asynchronously and never blocks Emacs. To restore the old focus-stealing
behaviour, set:

```elisp
(setq splotch-apple-return-focus-after-play nil)
```

## License

Copyright (C) Daniel Martins

Distributed under the GPL v3 License. See COPYING for further details.

[app-list]: https://developer.spotify.com/dashboard
[app-create]: https://developer.spotify.com/dashboard/create
[kbd-conv]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Key-Binding-Conventions.html
