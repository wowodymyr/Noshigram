# Noshigram

Telegram client for jailbroken iPhones and iPads on iOS 7 and newer (armv7 and arm64 in one binary), in the spirit of Telegram for iOS of the 2014 to 2018 years.

The look follows Telegram 4.x on iOS 7: flat light bars, the Contacts / Calls / Chats / Settings tab bar, grouped white lists on grey, the user and group info
screens with the photo at the left and actions as blue rows, the system action sheets, and a flat story viewer. No gloss, no Material Design.

## Install

Download the latest `.deb` or `.ipa` from [Releases](https://github.com/wowodymyr/Noshigram/releases):

- `.deb`: `dpkg -i Noshigram-*.deb` on a jailbroken device (or open it with Filza)
- `.ipa`: install with AppSync Unified, TrollStore or any other IPA installer

The app checks Releases itself and offers new versions in Settings → Update.

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

Needs [Theos](https://theos.dev) with the iPhoneOS14.5 SDK in `$THEOS/sdks` and a current clang (`clang-21` or `clang`) on the host for OpenSSL, which the clang 11 of the Theos toolchain miscompiles for armv7.

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

Noshigram: [wowodymyr](https://github.com/wowodymyr), [koke228666](https://github.com/koke228666), Claude (Anthropic).

exteria developers: sqmrak, QWERTYU1OPZ, LimeDev, menstry, anazerka, loveiOS6, nestorvashenko, svcayon4ik, illyagif.

## License

[exteria license](LICENSE); rights granted earlier under [GPL v3](LICENSE.gpl-3.0) remain. Third-party code, fonts, sounds and artwork keep their own licenses (`resources/licenses`, `resources/fonts`). The emoji pack is Apple artwork and is not licensed for redistribution, see `resources/emoji/NOTICE.txt`.
