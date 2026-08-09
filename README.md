# CFD — Current Folder Downloader

A tiny Windows CLI tool that makes downloading from Hugging Face as easy as `npm install`.

Type `cfd` and paste your `hf download` command in any folder, and CFD calls HF to download straight into that folder.

## Features

- **Callable from anywhere** — install once, then run `cfd` from any folder, just like `npm` or `git`.
- **Downloads to your current folder** — no more moving a the downloaded files around drives.
- **Background download queue** — paste a second (or third, or tenth) `cfd` + `hf download` command while the first is still running. Each one queues up and starts automatically once the folder is free.
- **Per-folder queues** — downloads to different folders run in parallel; only downloads *into the same folder* wait their turn (since `hf download` can only use one `.cache` at a time).
- **Crash recovery** — if your PC crashes or the worker window gets closed mid-download, `cfd force continue` / `cfd fc` picks up right where it left off.
- **Self-installing** — adds itself to your PATH, cleans up any old copies, and can uninstall itself just as easily.

## Requirements

- Windows with `cmd.exe`
- [Hugging Face CLI](https://huggingface.co/docs/huggingface_hub/guides/cli) installed and on your PATH:
  ```
  pip install -U "huggingface_hub[cli]"
  ```
- PowerShell (included by default on Windows) — used internally for PATH management, no manual setup needed.

## Installation

1. Download `cfd.bat` and `install.bat` from this repo and put them in the same folder.
2. Double-click `install.bat` (or run it from a terminal).
3. Close and reopen any terminal windows.

That's it — `install.bat`:
- Copies `cfd.bat` to `%LOCALAPPDATA%\CFD`
- Adds that folder to your user `PATH` (no admin rights needed)
- Finds and removes any stray `cfd.bat` elsewhere on your `PATH` so there's no conflict
- Re-running it later safely overwrites the existing install with a newer version of `cfd.bat`

## Usage

Open a terminal in whatever folder you want the files to land in, type `cfd` and paste the "Download with hf CLI" command from the [Hugging Face website](https://huggingface.co). For example:

```
cfd hf download hf://prism-ml/Bonsai-27B-gguf/Bonsai-27B-Q1_0.gguf
```

A **CFD Worker** window opens and starts downloading into your current folder. Your terminal is free immediately — `cd` into another folder or paste another `cfd` command right away.

If you paste another download command **for the same folder** while one is already running, it's added to that folder's queue instead of starting a second worker:

```
cfd hf download hf://another-org/another-model
[CFD] A download is already running in this folder.
[CFD] Added to queue at position 2: hf download hf://another-org/another-model
```

Once the current download finishes (and its temporary `.cache` folder is cleaned up), the worker automatically starts the next queued item — repeating until the queue is empty, at which point the worker window closes itself.

## Commands

| Command | Alias | Description |
|---|---|---|
| `cfd hf download <link>` | | Downloads to the current folder, or queues if a download is already running here |
| `cfd status` | `cfd queue` | Shows whether a worker is active, what's currently downloading, and what's queued |
| `cfd continue` | `cfd c` | Resumes downloads after a crash/interruption, reusing the existing `.cache` |
| `cfd unlock` | `cfd u` | Clears a stuck lock file (e.g. after force-closing a worker window) |
| `cfd force continue` | `cfd fc` | Unlocks and resumes in one step — use when you're sure no worker is still running |
| `cfd clear` | | Wipes the pending queue for the current folder |
| `cfd uninstall` | | Removes `cfd` from PATH and deletes its installed files |

## Recovering from a crash

If your PC crashes or you force-close a CFD Worker window mid-download, reopen the same folder and run:

```
cfd fc
```

This clears the stale lock and re-queues whatever was in progress, ahead of anything still waiting. `hf download` handles the rest — it checks the existing `.cache` against what's already on disk and resumes/verifies rather than starting over.

If you'd rather confirm nothing is actually still running before resuming, use the two-step version instead:

```
cfd unlock
cfd continue
```

## Uninstalling

```
cfd uninstall
```

This removes the install folder from your `PATH` and deletes the installed files. Close and reopen your terminal afterward.

## How it works

`cfd` is a single `.bat` file. When you run a download command, it:

1. Validates the command contains `hf download`
2. Appends it to a per-folder queue file (`.cfd.queue`)
3. If no worker is already running in that folder (no `.cfd.lock`), spawns a detached **CFD Worker** window that processes the queue

The worker pulls one command at a time from the queue, writes it to `.cfd.current` while it's running (so a crash leaves behind a record of exactly what was interrupted), runs it with `--local-dir` pointed at the target folder, and cleans up the `.cache` folder on success. When the queue is empty, it deletes the lock file and closes itself.

## License

Apache-2.0
