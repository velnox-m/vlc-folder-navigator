# folder_nav.lua

Folder-aware **Previous / Next** for VLC, the way MPC-HC do it.

Open any video or audio file, and VLC's normal Next / Previous buttons, hotkeys and media keys move through the other files in the same folder. No manual playlist building and no reopening files.

## How it works

A small Lua interface runs in the background and checks twice a second which file is playing. When you open a file that VLC did not get from this script, it:

1. Lists the media files in that file's folder and sorts them (natural order by default, so `ep2` comes before `ep10`).
2. Replaces the playlist with that folder, keeping your current file playing without interruption, so the order is `earlier files → current file → later files`.

Files you pick from the script's own playlist are left alone, so navigating never triggers a rebuild.

## Requirements

- VLC 3.x on Windows, Linux or macOS.
- The script uses only Lua functions that exist in VLC 3.0 (`vlc.io.readdir`, `vlc.net.stat`, `vlc.playlist.*`, `vlc.input.item`), and I checked them against the VLC 3.0 source.
- VLC 2.x is untested.

## Installation

1. Copy `folder_nav.lua` into VLC's **user** `lua/intf` folder (create the folders if they do not exist):

   | OS | Folder |
   |---|---|
   | Windows | `%APPDATA%\vlc\lua\intf\` |
   | Linux | `~/.local/share/vlc/lua/intf/` |
   | macOS | `~/Library/Application Support/org.videolan.vlc/lua/intf/` |

   You can also use the system folder (`C:\Program Files\VideoLAN\VLC\lua\intf\` on Windows), which needs admin rights.

2. Enable it in VLC:
   - Open **Tools → Preferences** and set **Show settings** to **All**.
   - Go to **Interface → Main interfaces** and tick **Lua interpreter**.
   - Expand **Main interfaces → Lua**, and in **Lua interface** type `folder_nav`.
   - Click **Save** and restart VLC.

   Or from the command line, without changing any settings:

   ```
   vlc --extraintf=luaintf --lua-intf=folder_nav
   ```

The "Lua HTTP" and "Lua Telnet" settings on that page are unrelated, so leave them as they are.

## Configuration

Options go in the **Lua config** field on the same preferences page (or after `--lua-config` on the command line). The format is:

```
folder_nav={depth=0,sort="name",loop=false,preserve_custom=true,debug=false}
```

Every option is optional.

| Option | Default | Description |
|---|---|---|
| `depth` | `0` | How many levels of subfolders to include. `0` means only the current folder. Subfolder files are placed after the current folder's remaining files. |
| `sort` | `"name"` | `name`, `mtime` (modified), `ctime` (created) or `size`. Add `_desc` for descending, for example `"mtime_desc"`. |
| `loop` | `false` | Turn playlist loop on so Next wraps from the last file to the first (and Previous the other way). |
| `preserve_custom` | `true` | If you open several files at once or build your own playlist, the script leaves it alone. Set to `false` to always rebuild from the folder. |
| `debug` | `false` | Write activity to VLC's message log (**Tools → Messages**). |

Examples:

```
folder_nav={sort="mtime_desc"}
folder_nav={depth=1,loop=true}
folder_nav={sort="size_desc",debug=true}
```

On the command line, wrap the value in quotes:

```
vlc --extraintf=luaintf --lua-intf=folder_nav --lua-config "folder_nav={sort='mtime',loop=true}"
```

## Behavior notes

- **Sorting:** name sorting is case-insensitive and natural, so `Episode 2` sorts before `Episode 10`. Ties in date or size fall back to name order.
- **Supported files:** common video and audio extensions are queued. The file you open is always included, even if its extension is not on the list.
- **Local files only:** streams and URLs are ignored. Network shares work if they are reachable as normal file paths.
- **Replacing the playlist:** when you open a single file, anything previously in the playlist is replaced by that file's folder. This matches how VLC treats "Open File" anyway. Turn on `preserve_custom` (the default) to protect playlists you built yourself.
- **Start and end of the folder:** with `loop=false`, Previous on the first file and Next on the last file do nothing, as in a normal VLC playlist.
- **Fallback:** if VLC refuses to reorder the playlist, the script turns on playlist loop so Previous still reaches the earlier files by wrapping around.

## Troubleshooting

- **Nothing happens:** confirm the file is in the right `lua/intf` folder and that **Lua interface** is exactly `folder_nav`. Set `debug=true`, then check **Tools → Messages** for `[folder_nav]` lines.
- **Config seems ignored:** the value must start with `folder_nav={` and end with `}`, and strings need quotes, for example `sort="mtime"`.
- **Errors:** runtime errors are written to the VLC message log under `[folder_nav]`.

## License

Free to use, modify and share.

## Acknowledgments & Credits

This project builds upon the foundational work of earlier community extensions and scripts for VLC:
- **[VlcPrevNext](https://github.com/djomlastic/VlcPrevNext)** by [djomlastic](https://github.com/djomlastic) — Inspired the playlist re-ordering/movement logic.
- **[next_in_folder.lua](https://github.com/diegogliarte/vlc-next-in-folder)** by [diegogliarte](https://github.com/diegogliarte) — Inspired the background interface loop structure.

`vlc-folder-navigator` refactors these concepts into the folder_nav.lua script.
