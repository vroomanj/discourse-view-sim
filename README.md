# discourse-view-sim

A tiny Discourse plugin that exposes one authenticated endpoint to **increment a
topic's view counter directly**.

Discourse only counts a topic view from a genuine browser page-load (the Ember
app boots and registers the view with a full browser fingerprint). No HTTP
client — anonymous, API-key, or even a fully logged-in session — can trigger it,
and real views are deduped to ~1 per user/topic/day. This plugin writes the
`topic.views` column itself so an **owner-operated, fully-disclosed** research
agent can simulate views in real time, with no browser, no dedup, and any volume.

> Intended for a self-hosted forum you own where AI operation is openly
> disclosed. Inflating view counts on a forum you do not control, or without
> disclosure, is not a supported use.

## Endpoint

```
POST /view-sim/bump/:topic_id
Header: X-View-Sim-Secret: <your secret>
Body:   count=<1..50>            # optional, defaults to 1
```

Response:

```json
{ "topic_id": 123, "added": 3, "views": 1274 }
```

Errors: `403` (bad/missing secret or rate-limited), `404` (topic missing or not a
regular topic).

## Settings (Admin → Settings → Plugins)

| Setting | Meaning |
|---|---|
| `view_sim_enabled` | Master on/off for the endpoint. |
| `view_sim_secret` | Shared secret required in the `X-View-Sim-Secret` header. **Set a long random value.** |
| `view_sim_max_bumps_per_minute` | Per-IP rate cap (default 300). |

## Install

### Docker (standard `discourse_docker`)

1. Add to `containers/app.yml` so it survives rebuilds:
   ```yaml
   hooks:
     after_code:
       - exec:
           cd: $home/plugins
           cmd:
             - git clone https://github.com/vroomanj/discourse-view-sim.git
   ```
2. `cd /var/discourse && ./launcher rebuild app`
3. Set `view_sim_secret` in Admin → Settings → Plugins.

### Non-Docker (source install)

This plugin is **server-only** (no JS/CSS, no migrations), so there is no asset
precompile or `db:migrate` step — copy it in and restart the app.

```bash
sudo su - discourse                 # the app user
cd /var/www/discourse               # your Discourse source dir
git clone https://github.com/vroomanj/discourse-view-sim.git plugins/discourse-view-sim
sudo systemctl restart discourse-puma   # or your puma/unicorn service
```

Then set `view_sim_secret` in Admin → Settings → Plugins.

## Smoke test

```bash
curl -s -X POST https://yourforum/view-sim/bump/123 \
     -H "X-View-Sim-Secret: YOUR_SECRET" -d "count=1"
# -> {"topic_id":123,"added":1,"views":124}
```

## Calling it from an agent (Python / httpx)

```python
async def bump_view(client, topic_id, count=1):
    await client.post(f"/view-sim/bump/{topic_id}",
                      headers={"X-View-Sim-Secret": VIEW_SIM_SECRET},
                      data={"count": count})
```

## Security notes

- Treat `view_sim_secret` like an API key. The endpoint can inflate views if it
  leaks; the per-IP rate limit is a backstop, not a substitute for keeping the
  secret private. Consider an nginx IP allowlist if the agent runs from a fixed
  address.
- The write is a single `UPDATE topics SET views = views + N`; `count` is
  integer-clamped (1..50) so it can't be used for SQL injection.

## Compatibility

Uses only stable Discourse APIs (`ApplicationController`, `Topic`,
`RateLimiter`, engine routing). After a major Discourse upgrade, restart the app;
if the controller/routing API ever changes, the ~40 lines in `plugin.rb` are
trivial to adjust.

## License

MIT — see [LICENSE](LICENSE).
