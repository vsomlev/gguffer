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

## Associate it with `.gguf` files

In Finder: right-click any `.gguf` → **Get Info** → **Open with:** → *gguffer* →
**Change All…**

## The window

| Part | What it does |
| --- | --- |
| **Start** / **Stop** | Stop sends SIGINT, escalating to SIGTERM then SIGKILL. |
| **Open llama UI** | Opens the address the server announced, in your browser. |
| Log | Server output, following the tail unless you scroll up. |

The status tracks the model rather than just the process:

| | | |
| --- | --- | --- |
| ❔ grey | **Not loaded** | nothing started yet |
| 🔄 yellow, spinning | **Loading** | llama-server is up, still loading weights |
| ✅ green | **Running (8080)** | the model is loaded and the server is listening, on the port it announced |
| ⛔️ red | **Stopped** | the server is gone — hover for why |

The menus:

* `Server ▸ Start` / `Stop` (⌘S) — same as the toolbar button.
* `Server ▸ Start with Params…` (⌥⌘S) — asks for extra `llama-server` flags
  before starting. **Option-clicking the Start button** does the same.
* `Server ▸ Open llama UI` (⌘L) — same as the toolbar button - opens the ollama chat UI in your browser.
* `File ▸ Open Model…` (⌘O) — switches to a different model in the same window.
* `Server ▸ Copy Command` (⌥⌘C) — copies shell command for running the model.

## Settings

* **Load model on start** — starts llama-server as soon as a model is opened,
  whether the app was launched with it or you picked it with Open Model. It
  applies to the *next* model you open; turning it on does not start the model
  already sitting in the window. Off by default.

* **Reasoning** — adds `--reasoning on` / `off` / `auto` to every run. The
  fourth choice, *Don't pass the flag*, leaves it off the command line entirely
  so llama-server uses its own default. Not passed by default.
* **Extra parameters** — added to every run, whatever the model.

## Extra parameters

Everything after the model on the command line comes from three places, in this
order:

```
llama-server -m <model> [--reasoning …] [Settings extra parameters] [this model's own]
```

The model's own parameters come last on purpose: llama-server takes the last
occurrence of a flag, so a model can override anything the settings set.

There is no parameters field in the window. `Server ▸ Start with Params…` (⌥⌘S),
or Option-click **Start**, opens a dialog showing what this model will use — its
own parameters, or the ones from Settings when it has none of its own. Edit them
and they become this model's own, saved in `.gguffer.json`; leave them alone and
nothing is saved, so the model keeps following Settings.

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
