<p align="center">
  <img src="Resources/icon/gguffer.png" alt="gguffer" width="160">
</p>

<h1 align="center">gguffer</h1>

Simple app to run a llama-server in its own window when double-clicking a `.gguf` file, instead of fiddling with a terminal. The server runs as a child of the app and its log streams into the window.

## Build and install

```bash
./build.sh
```

Compiles `build/gguffer.app` (AppKit, no dependencies — just `swiftc` from the
Command Line Tools) and writes a disk image to `dist/`.

The app is not notarized. A disk image downloaded from elsewhere
is therefore quarantined: right-click the app and choose **Open** the first
time, or `xattr -d com.apple.quarantine /Applications/gguffer.app`.

## Config file

One `.gguffer.json` per folder, containing entries for the models in that folder that have been started with the app with non-default parameters:

```json
{
  "*": "--port 8080 -ngl 99",
  "Qwen3.5-4B-Q4_K_M.gguf": "--port 8081 -c 32768"
}
```

## License

[MIT](LICENSE). Do what you like with it.
