# Publishing quicktui-herdr

This file is documentation only. The steps below create a public GitHub
repository, push code, and list the plugin in the Herdr Marketplace. Each one
needs separate, explicit authorization from the maintainer. Do not run them
from an agent task that did not grant that authorization.

Target repository: `quicktui/quicktui-herdr` (GitHub organization `quicktui`).

## First publication

1. Create the public repository `quicktui/quicktui-herdr` with
   `herdr-plugin.toml` at the root.
2. Add the remote and push the reviewed `main` history and its tags. Do not
   force-push published tags.

   ```sh
   git remote add origin git@github.com:quicktui/quicktui-herdr.git
   git push -u origin main
   git push origin --tags
   ```

3. Set the repository description. The Marketplace card shows it next to the
   star count and the plugin name and version. Reuse the manifest
   `description`:

   ```sh
   gh repo edit quicktui/quicktui-herdr \
     --description "Use Herdr from your iPhone or Android phone with QuickTUI: native mobile app, one-step install, QR pairing, and an optional end-to-end encrypted relay." \
     --homepage "https://quicktui.ai/?ref=herdr"
   ```

4. Add the topic `herdr-plugin`. The Marketplace index is an automatic,
   unreviewed GitHub topic crawl that refreshes about every 30 minutes.
   See https://herdr.dev/docs/marketplace/

   ```sh
   gh repo edit quicktui/quicktui-herdr --add-topic herdr-plugin
   ```

5. Verify the listing: after the next crawl, the plugin appears on the
   Marketplace with the expected name, version, and description, and this
   works on a clean machine:

   ```sh
   herdr plugin install quicktui/quicktui-herdr
   herdr plugin list --plugin ai.quicktui
   ```

6. Keep `min_herdr_version` at the oldest Herdr that QuickTUI Server supports
   (`0.9.0` since `server2-20261026-01`). Raise it when the server or the
   plugin needs a newer Herdr.

## Version sync with QuickTUI stable server

The manifest `version` equals the latest published QuickTUI stable server tag
(`server2-YYYYMMDD-NN`; preview tags do not count). After each server2 stable
release:

1. On `develop`, set `version` in `herdr-plugin.toml` to the new tag.
2. Run `sh tests/run.sh`, then commit on `develop`.
3. Bring the commit to `main` with a fast-forward, and create the tag on that
   `main` commit:

   ```sh
   git switch develop
   git commit -am "Sync plugin version to server2-YYYYMMDD-NN"
   git switch main
   git merge --ff-only develop
   git tag server2-YYYYMMDD-NN
   git switch develop
   ```

4. Push `main` and the tag (only after publication is authorized; before
   that, keep the commits and tag local):

   ```sh
   git push origin main develop
   git push origin server2-YYYYMMDD-NN
   ```

## Trust model

Herdr does not review Marketplace plugins. Users inspect the manifest and
scripts before installing. The install entry runs the official QuickTUI
installer only after the user confirms in the pane; keep that behavior and the
README description of it in sync.
