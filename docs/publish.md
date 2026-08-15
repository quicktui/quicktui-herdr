# Publishing quicktui-herdr

This file is documentation only. It does not create a GitHub repository, push
code, add a topic, or register the plugin in the Herdr Marketplace.

Current authorization stops at the local repository
`/home/dualf/works/quicktui-herdr`.

## Later, after explicit authorization

1. Create a public GitHub repository with `herdr-plugin.toml` at the root.
2. Push the reviewed `develop` / `main` history. Do not force-push published
   tags.
3. Add the GitHub topic `herdr-plugin`. The Marketplace index is an automatic,
   unreviewed GitHub topic crawl and refreshes about every 30 minutes.
   See https://herdr.dev/docs/marketplace/
4. Users can then install with:

   ```sh
   herdr plugin install owner/repo
   ```

5. Keep `min_herdr_version = "0.8.0"` until the plugin actually needs a newer
   Herdr API.

## Do not do these from this repository today

- `git remote add` / `git push`
- Creating GitHub topics
- `herdr plugin install` from a guessed owner/repo
- Uploading Marketplace assets

Herdr does not review Marketplace plugins. The trust model is: users inspect
the manifest and scripts before linking or installing.
