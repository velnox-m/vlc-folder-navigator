# VLC Folder Navigator (folder_nav.lua)

> Automatically play the next or previous media file in the same folder using VLC Media Player's native buttons, hotkeys, and media keys—just like MPC-HC.

## What is this?

**VLC Folder Navigator** is a background Lua interface script for VLC Media Player that solves VLC's missing folder-navigation behavior. By default, VLC requires you to manually load folders or open files individually. With this script, when you open any single video or audio file, it automatically queues all other media files in that directory into your playlist so you can seamlessly skip forward and backward through an entire folder.

## How it works

A small Lua interface runs in the background and checks twice a second which file is playing. When you open a file that VLC did not get from this script, it:

1. Lists the media files in that file's folder and sorts them (natural order by default, so `ep2` comes before `ep10`).
2. Replaces the playlist with that folder, keeping your current file playing without interruption, so the order is `earlier files → current file → later files`.

Files you pick from the script's own playlist are left alone, so navigating never triggers a rebuild.

## Requirements

- **VLC 3.x & +** on Windows, Linux, or macOS (tested on VLC 3.0.23, 3.0.24 on windows).
- **VLC 2.x compatible:** Includes automatic API fallbacks for VLC 3+ (`vlc.player.item`, `vlc.playlist.list`, `vlc.io.stat`) and VLC 2.x (`vlc.net.opendir`, `vlc.net.stat`).

## Installation

1. Copy `folder_nav.lua` into VLC's **user** `lua/intf` folder (create the folders if they do not exist):

   | OS | Folder |
   |---|---|
   | Windows | `%APPDATA%\vlc\lua\intf\` |
   | Linux | `~/.local/share/vlc/lua/intf/` |
   | macOS | `~/Library/Application Support/org.videolan.vlc/lua/intf/` |

   *(You can also use the system folder `C:\Program Files\VideoLAN\VLC\lua\intf\` on Windows, which requires admin rights, or `VLC\lua\intf\` for Portable VLC.)*

2. Enable it in VLC:
   - Open **Tools → Preferences** (`Ctrl + P`) and set **Show settings** (bottom-left) to **All**.
   - Go to **Interface → Main interfaces**, and in the **Extra interface modules** text box at the bottom, type `luaintf`.  
     *(Note: Do **not** tick the "Lua interpreter" checkbox above it—on Windows, that checkbox writes `lua` instead of `luaintf`, which opens a black command-line console window and ignores custom scripts.)*
   - Expand **Main interfaces → Lua**, and in **Lua interface** type `folder_nav`.
   - Click **Save** and restart VLC.

   Or run VLC from the command line without changing settings:

   ```sh
   vlc --extraintf=luaintf --lua-intf=folder_nav
   ```
## License

Free to use, modify and share.

## Acknowledgments & Credits

This project builds upon the foundational work of earlier community extensions and scripts for VLC:
- **[VlcPrevNext](https://github.com/djomlastic/vlc-prev-next)** by [djomlastic](https://github.com/djomlastic) — Inspired the playlist re-ordering/movement logic.
- **[next_in_folder.lua](https://github.com/diegogliarte/vlc-next-in-folder)** by [diegogliarte](https://github.com/diegogliarte) — Inspired the background interface loop structure.

`vlc-folder-navigator` refactors these concepts into the folder_nav.lua script.
