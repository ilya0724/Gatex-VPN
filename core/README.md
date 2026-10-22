# gatex-core

A thin wrapper around [Xray-core](https://github.com/XTLS/Xray-core)
(MPL-2.0, unmodified, pinned in `go.mod`).

- `gatexcore/` is the API both platforms use; it only uses types gomobile
  can bind, so it is also the Android library.
- `cmd/gatex-core` is the desktop helper:
  `run -c config.json -watch-stdin`, `check -c`, `delay -c`, `version`.

To update Xray, point `go.mod` at a newer tag's commit
(`go get github.com/xtls/xray-core@<commit>`), run `go mod tidy`, then the
app tests with `GATEX_CORE` set.
