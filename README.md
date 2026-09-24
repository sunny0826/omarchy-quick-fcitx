# Quick Fcitx / 快速输入法

`sunny0826.quick-fcitx` — an [Omarchy](https://omarchy.org/) shell plugin that shows your fcitx5 input-method state in the bar, switches Chinese/English with a single left-Shift tap, and manages input methods from a panel.

一个 [Omarchy](https://omarchy.org/) shell 插件：状态栏显示输入法 **中/en** 状态、**轻点左 Shift** 快速切换中英文、面板内**安装引擎 / 导入 Rime 方案 / 管理输入法列表**。

## Features / 功能

- **Bar widget** — shows `中` while a Chinese input method is active, `en` otherwise, `--` when fcitx5 is not running. Click opens the management panel.
  **状态栏**——中文输入法激活时显示 `中`，否则 `en`，fcitx5 未运行显示 `--`；点击打开管理面板。
- **Left-Shift tap** — tap left Shift alone to toggle 中/英. Shift+letter still types uppercase; any chord involving another key never triggers the toggle. Opt-in via the panel (adds a marker-managed block to `~/.config/hypr/bindings.lua`, removable at any time).
  **轻点左 Shift 切换**——单独按一下左 Shift 切换中/英；Shift+字母 照常打大写，组合键不会误触发。面板中显式开启（向 `~/.config/hypr/bindings.lua` 写入 marker 托管块，可随时移除）。
- **Panel** — switch 中/英 manually, restart fcitx5, install input-method engines, import Rime schemas, add/remove input methods in the current profile (profile edits stop fcitx5 first, verify the result over D-Bus, and roll back if fcitx5 rejects it; the addable list only shows what fcitx5 itself can load).
  **管理面板**——手动切换中/英、重启 fcitx5、安装输入法引擎包、导入 Rime 方案、增删当前配置组的输入法（增删采用"停→改→启→D-Bus 验证，拒绝即回滚"，可添加列表只列 fcitx5 真正能加载的输入法）。

## Requirements / 依赖

- Omarchy 4 (Quattro) with fcitx5 running (`omarchy-fcitx5.service`)
- `fcitx5-remote`, `jq`, `dbus-monitor`, `busctl`
- Omarchy 4（Quattro）+ 正在运行的 fcitx5；命令依赖 `fcitx5-remote`、`jq`、`dbus-monitor`、`busctl`

## Install / 安装

```bash
omarchy plugin add https://github.com/sunny0826/omarchy-quick-fcitx.git --enable --yes
```

Then enable the left-Shift toggle from the panel (or add the block manually, see below).

装完后在面板中开启“轻点左 Shift 切换”（或按下方说明手动添加托管块）。

## Update / 更新

```bash
omarchy plugin update sunny0826.quick-fcitx --yes
```

## Uninstall / 卸载

```bash
# 1. remove the left-Shift block if you enabled it
scripts/install-keybind --remove   # run from a checkout, or via the panel toggle first
# 2. remove the plugin
omarchy plugin remove sunny0826.quick-fcitx --yes
# 3. remove the widget entry {"id":"sunny0826.quick-fcitx"} from
#    ~/.config/omarchy/shell.json bar layout (if still present)
```

Uninstall never touches fcitx5 profiles, Rime data, or installed packages.
卸载不修改 fcitx5 配置、Rime 数据，也不卸载任何软件包。

## Left-Shift toggle: manual setup / 手动开启左Shift切换

The panel toggle writes this idempotent block into `~/.config/hypr/bindings.lua` (and removes it on demand):

```lua
-- >>> sunny0826.quick-fcitx (managed) >>>
if not _quick_fcitx_state then
  _quick_fcitx_state = { down = false, tainted = false }
  hl.on("input.keyboard.key", function(keycode, _, state)
    if not _quick_fcitx_state then _quick_fcitx_state = { down = false, tainted = false } end
    if keycode == 50 then
      if state == 1 then
        _quick_fcitx_state.down = true
        _quick_fcitx_state.tainted = false
      elseif _quick_fcitx_state.down then
        _quick_fcitx_state.down = false
        if not _quick_fcitx_state.tainted then
          hl.exec_cmd("<plugin-dir>/scripts/fcitxctl toggle")
        end
      end
    elseif _quick_fcitx_state.down then
      _quick_fcitx_state.tainted = true
    end
  end)
end
-- <<< sunny0826.quick-fcitx <<<
```

`<plugin-dir>` is `~/.config/omarchy/plugins/sunny0826.quick-fcitx`.

## Privileges / 提权说明

The panel never runs `sudo` itself. Installing packages opens a visible terminal (`alacritty -e ...`) where you type your password; input-method list and Rime imports write only to `~/.config/fcitx5/profile` and `~/.local/share/fcitx5/rime/` with timestamped backups.
面板自身不执行 sudo：装包会打开可见终端让你输密码；输入法列表与 Rime 导入只写 `~/.config/fcitx5/profile` 和 `~/.local/share/fcitx5/rime/`，写入前自动做时间戳备份。

## Development / 开发

```bash
omarchy plugin validate .       # manifest schema check
./tests/fcitxctl-test.sh        # unit tests (PATH-stubbed, no fcitx5 needed)
rsync -a --delete ./ ~/.config/omarchy/plugins/sunny0826.quick-fcitx/   # local hot-reload deploy
```

## License / 许可证

MIT © sunny0826
