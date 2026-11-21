# Working on Noshigram

## Rules

- The target is a real iOS 5 device on armv7; arm64 starts at iOS 7. Anything newer than iOS 5 is used only behind a runtime check.
- Objective-C is manual reference counting. Don't turn on ARC.
- UIKit only on the main thread; background threads that create objects need their own autorelease pool.
- Logic that can be tested without UIKit goes into `core/` as C99, with a test in `tests/core`.
- Strings go into `resources/localization/en.lproj` first, then `ru.lproj`.

## Layout

```
app/          Objective-C: screens, views, platform glue
core/         C99: MTProto, TL, storage, chat logic, no UIKit
extension/    share extension
resources/    icons, sounds, strings, launch images
schemas/      TL schemas for tools/tlgen.py (make generate)
scripts/      dependency build, packaging helpers
tests/        host tests
tools/        asset and TL generators
third_party/  vendored libraries
```

## Build and test

See the README. Host tests have to be built with the system compiler, not the iOS toolchain:

```bash
cd tests && PATH=/usr/local/bin:/usr/bin:/bin make CC=gcc -j8 test
```

`make test-icons` checks the icon files (needs Pillow). `tools/make_assets.py icons|qrlogo|splash|launch` regenerates the app icon set from `resources/icons/source/telegram.png`.

## Device

Jailbroken devices only, the binary is signed with ldid. Crash log: `/var/mobile/Library/Caches/noshigram-crash.log`. To symbolicate it, keep the build that was installed and run `python3 scripts/symbolicate_crash.py crash.log /path/to/Noshigram --arch armv7`.

Old sshd on iOS 5/6 needs `-o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 -o Ciphers=+aes128-cbc` and `scp -O`.
