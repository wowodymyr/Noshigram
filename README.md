# noshigram

<p align="center">
  <img src="docs/banner.png" alt="noshigram">
</p>

<p align="center"><b>native telegram for old iphones and ipads: ios 5 and up, calls with video, stories, folders, the look of telegram for ios 6 and 7</b></p>

> [!NOTE]
> the ipa is signed with ldid, so it installs on a jailbroken device.

noshigram ("no shit telegram") is a fork of [exteria](https://github.com/sqmrak/exteria) with everything that is not telegram taken out: the material design look, the python plugins, the badges of the team, ayumoments, senko and the boykissers, the shiro vpn, and the meow build in favour of theos.

## devices

- armv7: ios 5 and later
- arm64: ios 7 and later
- iphone and ipad, one binary with both slices

## features

- chats, folders, archive, stories, polls, reactions, custom emoji
- reactions use the icons and animations of the server: still icons on the chips, a pop in the picker, a burst when one is put on a message. a free account keeps one reaction per message, Premium up to the limit the server names (3)
- stickers: static, animated and video
- voice notes, round videos, gifs, files, albums, flac music
- location picker and nearby places, OpenStreetMap previews
- calls: voice and video (vp8); voice chats of groups and channels, audio only
- translator: telegram, services and ai
- passcode lock, several accounts, login by phone or qr
- session files (`session-N.bin`) are sealed with chacha20-poly1305 under a random device key, kept in the keychain (this device only, after first unlock) or, where the keychain refuses the app, in `Application Support/Noshigram/session-key`. files from older builds are sealed on first read. restoring a backup onto another device signs the account out, since the key does not travel
- the look of telegram for ios 6 and 7: glossy bars, the classic bubbles and the blue of telegram, by day and by night
- in-app browser for web links, a sheet that slides up and is pulled down to close
- a font file of your own (`.ttf` or `.otf`) or Rubik for the whole app, in chat settings
- power saver, local notifications
- russian, english

## browser

web links open in noshigram, the system browser, or an installed chrome, firefox or brave, as chosen in the main settings. telegram links stay in the app. youtube track and playlist links (watch, playlist, shorts, live, embed, youtu.be) open in rewind when it is installed, whatever browser is chosen.

## proxy

add a `tg://proxy`, `tg://socks`, `t.me/proxy` or `t.me/socks` link on the welcome screen or in more settings.

- mtproto: plain, `dd` and `ee` secrets; socks5: username and password
- up to 64 links, kept in the keychain or in `Application Support/Noshigram/proxy-link`
- telegram connections use the proxy; calls and web pages do not

## for developers

- [CONTRIBUTORS.md](CONTRIBUTORS.md): build, test, layout, the c core, device install
- [docs/languages.md](docs/languages.md): add a language, from a `.strings` file or built into the app

## build

```bash
export THEOS=~/theos                 # with the iPhoneOS14.5 and iPhoneOS9.3 sdks in $THEOS/sdks
bash scripts/build_deps.sh           # openssl, libvpx and ffmpeg for both slices, into deps/
make test                            # host tests of the c core
make package                         # the deb
make package PACKAGE_FORMAT=ipa      # the ipa
```

api id and hash come from the environment or `local/credentials.env` (`NOSHI_API_ID`, `NOSHI_API_HASH`). the packages land in `packages/`.

- `make test-video`: video decoders under asan and ubsan, needs ffmpeg libraries, pkg-config and libvpx
- `scripts/check_legacy_symbols.sh <executable>`: imports of the armv7 slice against the ios 5 runtime, needs `NOSHI_TC` and `NOSHI_SDK_V5`

## install

```bash
make package install THEOS_DEVICE_IP=<device-ip>
```

the deb installs the bundle into `/Applications` on a rootful system (`/var/jb/Applications` on a rootless one); the postinst makes `mobile:wheel` the owner (or the app cannot change its own icon on ios 6) and runs `uicache`.

on ios 5 and 6 an app in `/Applications` gets no banners, no notification center entry and no settings row, because springboard gives notification settings to user apps only. the postinst runs `/Applications/Noshigram.app/Noshigram --system-notifications on` for that, and the postrm takes it back with `off`. it adds the `SBInternalAppTag` to the bundle's `Info.plist` and sets `SBShowInternalApps` in the springboard preferences (without it the icon of an internal app is hidden). the in-app update runs it again after it replaces the files. an ipa installed as a user app (ipainstaller, appsync) and the rootless `/var/jb` install need nothing, and ios 7 and later are left alone by the command.

## updates

on start the app asks `api.github.com` for the latest release and shows a notice when its tag is newer. a release needs `Noshigram-v<version>.ipa` and `Noshigram-v<version>.ipa.sha256`, the tag is `v<version>`.

- the update replaces the files of the running bundle on a writable jailbreak install in `/Applications`, `/var/jb/Applications` or the user app folder `/var/containers/Bundle/Application` (an ipa installed with ldid keeps the entitlement that allows the write; an apple-signed install does not, and its write probe fails); other installs open the release page
- the ipa must match its digest, or nothing is installed
- limits: 128 MiB, 4096 entries, four https redirects to github hosts

## paths

- accounts: `Library/Application Support/Noshigram/noshigram-<id>.db`
- crash log: `/var/mobile/Library/Caches/noshigram-crash.log`
- call trace: `/var/mobile/Documents/noshigram-call-trace.log`
- frame log: `Library/Caches/noshigram-perf.log`, on with `defaults write com.noshigram.app noshigram.perf -bool YES`

to resolve app frames in a copied crash log, use the executable of the exact reported build and architecture (needs `llvm-objdump` and `llvm-addr2line`):

```bash
python3 scripts/symbolicate_crash.py crash.log /path/to/Noshigram --arch armv7
```

## license

[noshigram license](LICENSE). rights already granted under [gpl v3](LICENSE.gpl-3.0) remain in effect. the emoji pack is apple artwork and is not licensed for redistribution, see `resources/emoji/NOTICE.txt`. fonts, codecs and sounds keep their licenses in `resources/licenses` and `resources/fonts`.
