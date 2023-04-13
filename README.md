# Syncstream

This is a tool that converts a public Spotify playlist to a Tidal playlist.

## Installation

```sh
go install github.com/michaeldbianchi/syncstream@latest
```

## Usage

```sh
cp .env.example .env
# Manually set tidal and spotify env vars

syncstream <spotify_playlist_id>
```


## Goals
* v0.1 - Import individual playlist + tracks from spotify to tidal
* v0.2 - Sync all playlists (or subset) from spotify to tiday
* Implement port and adapter pattern so sync is not bound to spotify -> tidal
* Figure out auth in a way that's not as rough

