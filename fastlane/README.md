fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate localized app screenshots via UI tests

### ios push_metadata

```sh
[bundle exec] fastlane ios push_metadata
```

Upload App Store metadata + screenshots to ASC (no binary, no review submission)

### ios register_bundle_id

```sh
[bundle exec] fastlane ios register_bundle_id
```

Ensure Bundle ID exists on Developer Portal (idempotent, via ASC API)

### ios ensure_app_on_asc

```sh
[bundle exec] fastlane ios ensure_app_on_asc
```

Ensure an App record exists on App Store Connect (idempotent)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
