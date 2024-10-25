# mkdir.yazi

Create directories in yazi without having to type a trailing slash at the end every time.

## Installation

```sh
# Linux/MacOS
git clone https://github.com/Sonico98/mkdir.yazi.git ~/.config/yazi/plugins/mkdir.yazi

# Windows
git clone https://github.com/Sonico98/mkdir.yazi.git %AppData%\yazi\config\plugins\mkdir.yazi
```

## Usage

Add this to your `keymap.toml`:

```toml
[[manager.prepend_keymap]]
on = [ "m", "k" ]
exec = "plugin mkdir"
desc = "Create a directory"
```
