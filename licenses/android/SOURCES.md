# Android Third-Party Notices

The APK embeds unmodified WireGuard Android tunnel 1.0.20260102.
WireGuard Android is copyright WireGuard LLC and contributors. Its Go backend
is copyright WireGuard LLC and contributors and is MIT-licensed.
Go and golang.org/x modules are copyright The Go Authors (BSD-3-Clause).

License texts were obtained from these version-specific upstream sources:

- https://raw.githubusercontent.com/WireGuard/wireguard-android/1.0.20260102/COPYING
- https://raw.githubusercontent.com/WireGuard/wireguard-go/f333402bd9cb/LICENSE
- https://raw.githubusercontent.com/golang/go/go1.23.1/LICENSE
- https://raw.githubusercontent.com/golang/crypto/v0.38.0/LICENSE
- https://raw.githubusercontent.com/golang/net/v0.40.0/LICENSE
- https://raw.githubusercontent.com/golang/sys/v0.33.0/LICENSE

Go dependency versions are specified in the tunnel release's
`tunnel/tools/libwg-go/go.mod`. The Android SDK/Kotlin/AndroidX dependencies
include Apache-2.0 components; embedded AndroidX license files are also extracted
from the actual APK into the distribution bundle. Flutter/Dart package notices
are extracted from the APK's generated `NOTICES.Z` rather than handwritten.

Distribute the complete release ZIP with these notices, not only a detached APK.
