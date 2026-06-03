# todo

A tiny CLI for short reminders that reprints them on every new shell.

## Build

```
zig build
```

The binary lands at `zig-out/bin/todo`. Install it on your `PATH` however you prefer (a symlink into `~/.local/bin` works).

## Usage

```
todo                              list active todos
todo -q                           same, silent if empty (use this in your shellrc)
todo -l <tag> [<tag>...]          filter by tag (OR match)
todo --all                        group active todos by tag, plus [untagged]
todo "text @tag1 @tag2"           add; trailing @tags are extracted
todo "call @@doctor for refill"   inline tag: stored as "@doctor", tag = doctor
todo -t urgent "text"             add with explicit tag (repeatable)
todo done                         list completed todos
todo done @tag [@tag...]          list completed todos with any listed tag (OR match)
todo done <id> [note]             mark complete; optional note is stored
todo clear --all                  soft-delete all active items
todo clear @tag [@tag...]         soft-delete active items having any listed tag
todo clear <id>                   soft-delete one active item by id
todo tag <id> +@tag -@tag         add/remove tags on an active item (repeatable)
todo tags                         list all tags with counts by state
todo color @tag #rrggbb           set a display color for a tag
todo color @tag                   unset display color for a tag
todo colors <file>                bulk-load tag colors from a file
```

Tags are case-insensitive and normalized to lowercase. They must match `[A-Za-z0-9_-]+`.

Listings show tags aligned to a pipe separator:

```
1. call the lab      | @urgent
2. buy milk          | @errand @quick
3. read the docs
```

### Tag colors

Assign a 24-bit RGB color to any tag so it appears highlighted in listings and the tags table:

```
todo color @urgent #ff0000
```

To load colors for several tags at once, put them in a plain text file — one `tag=#rrggbb` entry per line — and run:

```
todo colors mycolors.txt
```

Example file:

```
urgent=#ff0000
work=#5599ff
shopping=#00cc66
```

Empty lines are ignored. Tags are normalized (leading `@` is optional, name is lowercased).

### Tags table

`todo tags` prints a summary table of every tag that has ever appeared, with item counts broken down by state:

```
  tag    |  color  | active | done | cleared
---------|---------|--------|------|--------
@urgent  | #ff0000 |   3    |  1   |    0
@work    | #5599ff |   1    |  0   |    2
```

## Shell integration

Add this line to your `~/.bashrc` or `~/.zshrc`:

```bash
command -v todo >/dev/null && todo -q
```

The `command -v` guard keeps your shell from breaking if `todo` is ever missing.

## Storage

By default the database lives at `$XDG_DATA_HOME/todo/todo.sqlite` (falling back to `$HOME/.local/share/todo/todo.sqlite`). Override with `TODO_FILE=/some/path.sqlite`.

The file is SQLite. You can `sqlite3 ~/.local/share/todo/todo.sqlite` to poke at it.
