# autovod

Records `twitch.tv/cuistops` live with streamlink and pipes the stream straight
into YouTube via [youtubeuploader]. Nothing is stored: the recording never
touches a disk, so there is no PVC.

[AutoVOD] upstream ships no image and bakes config + credentials into its
Dockerfile at build time. `image/` rebuilds it without that: `AutoVOD.sh` is
pulled at a pinned commit, and the config and credentials come from a ConfigMap
and a Secret at runtime. Build it with the `autovod-image` workflow.

## How it runs

`AutoVOD.sh` loops forever: every 60 s it asks streamlink whether the channel is
live, and if it is, records up to `VIDEO_DURATION` (11h45, under YouTube's 12 h
cap) while youtubeuploader consumes the pipe. When the stream ends, streamlink
exits, the upload finalises and the loop resumes polling.

The entrypoint copies the mounts into `/workdir` because AutoVOD sources its
config from the cwd and youtubeuploader rewrites `request.token` in place.

## Secrets

`kv/autovod` in OpenBao, pulled by the `autovod` ExternalSecret:

| property | what |
| --- | --- |
| `client_secrets.json` | OAuth client (Desktop app) from the Google Cloud console |
| `request.token` | OAuth token minted by youtubeuploader, see below |
| `twitch_oauth_token` | Twitch account token, or `""` |

`twitch_oauth_token` is optional — streamlink 7.x strips ad segments on its own,
but an authenticated session gets an ad-free source instead of a gap. Note that
upstream's default `STREAMLINK_FLAGS` (`--twitch-disable-reruns`,
`--twitch-disable-hosting`) no longer exist in streamlink 7.x; `cuistops.config`
does not use them.

### Minting request.token

The OAuth consent flow needs a browser, so do it on a laptop, then push the
result into OpenBao:

```sh
# Google Cloud console: enable YouTube Data API v3, create an OAuth client of
# type "Desktop app", download it as client_secrets.json
youtubeuploader -filename /dev/null   # opens a browser, writes request.token

mise run vault:kv put kv/autovod \
  client_secrets.json=@client_secrets.json \
  request.token=@request.token \
  twitch_oauth_token=""
```

## The YouTube API catch

Until the OAuth consent screen passes Google's audit (count ~20 days), the
project stays in *Testing* and two things bite:

- every upload lands as **private and locked** — it cannot be made public, by
  the API or by hand. `VIDEO_VISIBILITY` is set to `private` to match reality.
- refresh tokens expire after **7 days**, so `request.token` has to be re-minted
  weekly. Publishing the app (even unverified) lifts that one.

Quota is 10 000 units/day and an upload costs 1600, so ~6 uploads/day.

[AutoVOD]: https://github.com/jenslys/autovod
[youtubeuploader]: https://github.com/porjo/youtubeuploader
