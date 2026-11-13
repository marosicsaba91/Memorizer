# Memorizer

A Flutter app for studying tables, playing practice rounds, and optionally syncing personal results.

## GitHub Pages

The workflow in `.github/workflows/deploy-web.yml` tests, builds, and deploys the web app on every push to `main`. It uses Flutter 3.50.0 and the committed `pubspec.lock` to keep dependency versions consistent.

One-time repository setup:

1. Open https://github.com/marosicsaba91/Memorizer/settings/pages.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. Commit and push the project changes, including the workflow and `pubspec.lock`.
4. Open the repository's **Actions** tab and watch **Deploy web to GitHub Pages**.

Expected address: https://marosicsaba91.github.io/Memorizer/

The workflow obtains the base path from GitHub Pages, so assets also work when the site is served from a repository subdirectory or a custom domain. To redeploy manually, use **Actions → Deploy web to GitHub Pages → Run workflow**.

Only the generated `build/web` folder is published. Personal settings and results remain in each browser's local storage; syncing uses the optional endpoint configured in Profile. Verify table downloads and endpoint upload/download from the deployed browser app as well as local play.

## Local web build

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --base-href /Memorizer/
```

For local browser development at the root path, use `flutter run -d chrome`.

See [GitHub's Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
