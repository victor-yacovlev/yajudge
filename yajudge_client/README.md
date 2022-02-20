## Client Frontend App for Yajudge

Implemented using [Flutter](https://flutter.dev).

### Prerequirements:

Flutter must have components enabled:
 - `web` - to build web interface target
 - `linux-desktop`, `macos-desktop` and `windows-desktop`
to build native desktop appications.

*NOTE:* Desktop applications are at early stage of development

To enable config run flutter tool like:
```shell
# this will download and enable Web target support
flutter config --enable-web

# enable desktop targets for macOS or Linux
flutter config --enable-macos-desktop
# or
flutter config --enable-linux-desktop
```

### Build

Type `make web-client` to build Web target or
`make native-client` to build Desktop target for current
platform. Result will be placed at `build/$TARGET` 
subdirectory corresponding selected target.

Web target will be used by third-party web server
like nginx or Apache or someone else, and contains
`index.html` as entry point.