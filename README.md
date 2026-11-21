# Noshigram

Telegram client for jailbroken iPhones and iPads on iOS 5 and newer (armv7 and arm64 in one binary), with the look of Telegram for iOS 6 and 7.

Noshigram is a fork of [exteria](https://github.com/sqmrak/exteria) by sqmrak. Removed from it:

- the Material Design interface (the classic one stays; features that only existed in the modern one were moved over)
- the Python plugin system
- developer badges and the team marks
- AyuMoments
- Senko, boykissers and other jokes
- the Shiro VPN
- crash reports sent to the upstream developer
- the meow build system, replaced with Theos

## Build

Needs [Theos](https://theos.dev) with the iPhoneOS14.5 and iPhoneOS9.3 SDKs in `$THEOS/sdks`.

```bash
export THEOS=~/theos
bash scripts/build_deps.sh            # openssl, libvpx, ffmpeg into deps/
export NOSHI_API_ID=... NOSHI_API_HASH=...   # or put them in local/credentials.env
make package                          # .deb in packages/
make package PACKAGE_FORMAT=ipa       # .ipa
make test                             # host tests of the C core
```

Install on a device: `make package install THEOS_DEVICE_IP=<ip>`.

## Credits

exteria developers: sqmrak, QWERTYU1OPZ, LimeDev, menstry, anazerka, loveiOS6, nestorvashenko, svcayon4ik, illyagif.

## License

[exteria license](LICENSE); rights granted earlier under [GPL v3](LICENSE.gpl-3.0) remain. Third-party code, fonts, sounds and artwork keep their own licenses (`resources/licenses`, `resources/fonts`). The emoji pack is Apple artwork and is not licensed for redistribution, see `resources/emoji/NOTICE.txt`.
