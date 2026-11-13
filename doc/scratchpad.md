# Named scratchpads

Fork-only feature (branch `scratchpad`). Code: `src/kwm/scratchpad.zig`, plus small hooks in
`binding.zig` (the action), `seat.zig` (key handler), `window.zig` (new-window hook and the
`scratchpad_hidden` flag in `is_visible_in`), `output.zig` (`occupied_tags` skips hidden pads) and
`context.zig` (cleanup, and the `single_tagset` loop skips hidden pads).

## How it works

- **Hidden:** the window's `scratchpad_hidden` flag is set. `is_visible_in` returns false for it
  whatever its tags or `sticky` say, so no tag view, "view all" bind or layout shows it, and the
  bar doesn't count its tag as occupied.
- **Show:** the flag is cleared, and it's made floating, sized, centred, given the current tag, and focused.
- **Hide:** the flag is set again; the window keeps its tag. Focus falls back to the previous
  window by itself.
- **Not running yet:** the key spawns the program, and the pad is shown as soon as its window appears.

## Config

Each keybind names one pad by `app_id` and/or `title` (the same pattern type as window rules),
gives the command that starts it, and its size as a fraction of the output:

```zig
.{
    .keysym = "s",
    .modifiers = .{ .mod4 = true },
    .event = .{ .click = .{ .pressed = .{ .toggle_scratchpad = .{
        .app_id = .{ .str = "ax-scratchpad" },
        .width = 0.7, .height = 0.8,
        .argv = .{ "foot", "--app-id", "ax-scratchpad" },
    } } } },
},
.{
    .keysym = "e",
    .modifiers = .{ .mod4 = true },
    .event = .{ .click = .{ .pressed = .{ .toggle_scratchpad = .{
        .title = .{ .str = "^emacs-scratchpad$", .regex = true },
        .width = 0.7, .height = 0.8,
        .argv = .{ "emacs", "-T", "emacs-scratchpad" },
    } } } },
},
```

`width`/`height` default to 0.5 and 0.6. Emacs can't set a per-frame app_id, so its pad matches
by title; `-T` pins the frame title so it doesn't change with the buffer.

Pressing the key:
- pad hidden, or shown on another output: show it here;
- pad shown and focused: hide it;
- pad shown but another window focused: focus the pad;
- no pad window: spawn `argv`. Further presses within 10 s don't spawn again (slow starters like
  Emacs), and the new window is shown when it first appears.

## Where the ideas come from

- **dwm, and why not its hidden tag.** dwm's scratchpad patches park the pad on a tag beyond the
  visible ones (`scratchtag = 1 << LENGTH(tags)`). The first version here did the same with bit 31,
  but "view all" (`0xffffffff`), tag cycling and the bar's occupied tags still reached it, so hiding
  is now a flag that the visibility check honours.
- **mango (and dwm's namedscratchpads patch), named pads.** The config interface follows mango's
  `toggle_named_scratchpad`: one bind per pad, matched by app_id or title, with a spawn command
  and a width/height ratio.
- **sway, "focus if visible".** A pad that's visible but not focused gets focused instead of
  hidden, as with sway's `scratchpad show`. Floating and centred, as in i3/sway.
- **kwm itself, focus fallback.** `focused_window()` returns the most recent window that's still
  visible, so hiding a pad needs no focus code.

## kwm/river specifics

- **Catching the new window:** the pad is caught right after window rules run (`.init` event),
  when river has already sent the app_id and title.
- **Fullscreen:** river renders a fullscreen window as the only window on its output, so nothing
  can be drawn over it. Showing a pad takes that window out of fullscreen (not restored on hide).
- **Config reload:** pending launches keep their own copies of the pad's patterns, so a reload
  can't leave them pointing at freed config memory.
