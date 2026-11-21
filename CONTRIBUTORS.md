# contributing to noshigram

how to build noshigram and how to work in it. user features are in [README.md](README.md), languages in [docs/languages.md](docs/languages.md).

## rules

- the baseline is real ios 5 on armv7, not a header that compiles with a low deployment target. arm64 starts at ios 7. one binary carries both slices
- objective-c uses manual reference counting. `retain`, `release`, `autorelease` and copied blocks are written by hand, `[super dealloc]` goes last. do not turn on arc
- a background thread that makes objects needs its own autorelease pool. uikit is touched on the main thread only
- an api newer than ios 5 is absent until a runtime check says otherwise: class, selector or symbol lookup, weak link, a fallback. do not send a selector because the sdk declares it
- logic that can be tested without uikit goes in `core/` as c99. uikit, controllers and platform glue go in `app/`
- no stubs, no silent no-ops, no ignored return values. a failure is returned, logged where it happened or shown
- no tls or certificate checks weakened to make something work
- a fallback needs a named failure it covers and a bound on its attempts
- every change that fixes a bug comes with a test that fails without it
- comments are english, lowercase, short, say why and not what, no final period, no dashes
- commit messages are lowercase and imperative, one line

## layout

```
app/        objective-c: controllers, views, platform glue
core/       c99: protocol, state, layout rules, parsers, no uikit
third_party vendored libraries, built from source
resources/  icons, fonts, sounds, strings, pems
schemas/    tl schemas the generator reads
scripts/    builds and packaging
tests/      host tests: c, the strings, video
tools/      asset generators and the tl generator
docs/       languages
local/      credentials.env, never committed
```

in `app/`:

- `lifecycle`: delegate, passcode lock, notifications, updater, crash log
- `net`: the objective-c face of the core: `noshi_session*.m` (one file per area of the api), models, caches, call engines
- `features`: screens, by area (`chats`, `auth`, `calls`, `stories`, `settings` and so on)
- `ui/shared`, `ui/classic`: views, theme, symbols, text layout. classic is the glossy chrome of telegram for ios 6 and 7, the only look the app has
- `media`: players, recorders, editors, viewers
- `platform`: settings stores, audio session, keychain
- `translate`: translator backends and language packs

## backend

the backend is the c core in `core/`. it is one static set of files, linked into the app and into the host tests. it has no uikit and no objective-c.

- `tl`: generated serializers and parsers, made from `schemas/*.tl` by `tools/tlgen.py` (`make generate`, `make check-generated`)
- `mtproto`: transports (tcp, mtproto proxy with `dd` and `ee` secrets, fake tls, socks5), handshake, keys, message framing, file transfer
- `crypto`, `auth`: aes, sha, srp, dh, passcode, login by phone and qr
- `client`: the rpc client over mtproto. one entry point for the app
- `updates`: update state, gaps, difference
- `storage`, `session`: the sqlite account db and the sealed `session-N.bin` files
- `chats`: dialogs, messages, media, profiles, stories, reactions, bots, stats. most of the logic the screens show
- `layout`: pure layout and rules for lists, text, motion, qr, welcome screens
- `calls`, `tgcalls`: voip: rtp, vp8, stun, turn, ice, srtp, sctp, group calls
- `media`, `video`, `emoji`, `notify`: id3, lrc, geo, photo edit, flac, vp8, yuv, emoji data, notification rules
- `base`: status codes, arena, byte buffers, release check, zip

how a call goes: a screen asks `NoshiSession` (`app/net`), which calls the core client, which builds a tl request, sends it over mtproto and returns a status. the answer is parsed in the core into a plain struct, and the session turns it into a model for the screen. results come back on the main thread.

the core returns specific statuses (`noshi_status.h`), not booleans. a function that writes a buffer takes its capacity. lengths from the network are capped before an allocation.

## build

needs a linux or macos host with [theos](https://theos.dev), its ios toolchain, the `iPhoneOS14.5.sdk` (the build) and the `iPhoneOS9.3.sdk` (the ios 5 start file `crt1.3.1.o`) in `$THEOS/sdks`.

```bash
export THEOS=~/theos
bash scripts/build_deps.sh           # openssl, libvpx and ffmpeg for armv7 and arm64, into deps/<slice>
make test
make -j16                            # both slices and the share extension
make package                         # the deb
make package PACKAGE_FORMAT=ipa      # the ipa
```

- `NOSHI_API_ID`, `NOSHI_API_HASH`: in the environment or in `local/credentials.env`. they go into a generated header in `build/` and never into the repository
- `DEPS`, `CRT_V7`: override where the static libraries and the armv7 start file are taken from
- `scripts/build_deps.sh` reads `NOSHI_TC`, `NOSHI_SDK`, `NOSHI_DEPS`, `NOSHI_SLICES` and `NOSHI_JOBS`

after the build, check the artifact and not only the exit code:

- `scripts/check_legacy_symbols.sh <executable>`: imports of the armv7 slice against the ios 5 runtime (needs `NOSHI_TC` and `NOSHI_SDK_V5`)
- `lipo -info` on the executable shows armv7 and arm64
- `unzip -l` on the ipa, `dpkg-deb -c` on the deb: layout, permissions, `Info.plist` version
- the version in `control` is the source, `packaging/Info.plist` and the extension plist follow it. do not bump it outside a release

## test

```bash
make test
make sanitize        # the c tests under asan and ubsan
make test-video      # decoders under sanitizers, needs ffmpeg libraries, pkg-config, libvpx
make test-icons
```

- c tests are `tests/core/test_*.c`, one binary each, built with `-Wall -Wextra -Werror -Wconversion`. they use fake servers (`fake_mt_server.c`, `fake_tcp_server.c`) on local sockets and byte vectors, never a public service
- `tests/python` checks the `.strings` files with a plain python 3
- the iphone toolchain on `PATH` breaks host builds (`gcc` becomes its clang, `--gdwarf-5` fails). run host tests with `PATH=/usr/local/bin:/usr/bin:/bin make CC=gcc -j8 test` from `tests/`
- tests prove the host side. what needs a real device is said in the commit and in the docs, not assumed

## add a feature

1. read the code around it, and the nearest screen that does something similar
2. put the parsing and the rules in `core/` with a test, then wire the objective-c side
3. `make generate` when a tl schema changed, and commit the generated tables with it
4. strings go in `resources/localization/en.lproj` first, then `ru.lproj`. a missing key falls back to english
5. icons come from `tools/make_assets.py`, svg sources in `tools/material` and `tools/symbols`. do not hand edit generated pngs
6. build both slices. a header change rebuilds a lot, run it in the background
7. update `README.md` or `docs/` when a user can see the change

## device

jailbroken devices only. the ipa is signed with ldid.

```bash
make package install THEOS_DEVICE_IP=<device-ip>
```

- the postinst makes `mobile:wheel` the owner of the bundle. a root-owned bundle breaks the icon change on ios 6, since the app rewrites its own `Info.plist` as `mobile`
- on ios 5 and 6 the postinst runs `/Applications/Noshigram.app/Noshigram --system-notifications on` before `uicache` (see the install section of the readme)
- old sshd needs `-o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 -o Ciphers=+aes128-cbc,aes256-cbc` on the command line, and `scp -O`. keep these out of `~/.ssh/config` and pass them by hand
- crash log: `/var/mobile/Library/Caches/noshigram-crash.log`. system reports: `/var/mobile/Library/Logs/CrashReporter`
- a tester's `build <hex>` line is the `LC_UUID` of the slice. match it with `llvm-dwarfdump --uuid` on the binary of that exact build, then `python3 scripts/symbolicate_crash.py crash.log /path/to/Noshigram --arch armv7`
- keep the ipa or deb of every build you hand out, or the crash cannot be named later

## do not

- commit `build/`, `local/credentials.env`, objects or stage directories
- bump a version, rewrite a checksum or publish a release outside a release
- edit `third_party` without a line in the matching `PATCHES` or notice
- raise the minimum ios version or drop armv7 to avoid a compatibility problem
- keep an old workaround next to its replacement
