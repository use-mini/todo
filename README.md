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
todo done <id>                    mark complete (use the id shown in listings)
todo clear --all                  soft-delete all active items
todo clear @tag [@tag...]         soft-delete active items having any listed tag
```

Tags are case-insensitive and normalized to lowercase. They must match `[A-Za-z0-9_-]+`.

Listings show tags aligned to a pipe separator:

```
1. call the lab      | @urgent
2. buy milk          | @errand @quick
3. read the docs
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
