const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const log = std.log.scoped(.scratchpad);

const build_options = @import("build_options");

const config = @import("config");

const Window = @import("window.zig");
const Output = @import("output.zig");
const Context = @import("context.zig");

const ctx = Context.get();

pub const Pattern = @typeInfo(@FieldType(config.WindowRule, "app_id")).optional.child;

const pending_timeout_ms = 10_000;

pub const Spec = struct {
    app_id: ?Pattern = null,
    title: ?Pattern = null,
    width: f32 = 0.5,
    height: f32 = 0.6,
    argv: []const []const u8,
};

const Pending = struct {
    app_id: ?Pattern,
    title: ?Pattern,
    width: f32,
    height: f32,
    since: Io.Timestamp,

    fn deinit(self: *Pending) void {
        if (self.app_id) |p| ctx.gpa.free(p.str);
        if (self.title) |p| ctx.gpa.free(p.str);
    }
};

var pending: std.ArrayList(Pending) = .empty;


pub fn deinit() void {
    for (pending.items) |*p| p.deinit();
    pending.deinit(ctx.gpa);
}


pub fn toggle(spec: *const Spec) void {
    const output = ctx.current_output orelse return;

    if (spec.app_id == null and spec.title == null) {
        log.err("toggle_scratchpad needs an app_id or a title", .{});
        return;
    }

    if (find(spec.app_id, spec.title)) |window| {
        drop_pending(spec);
        if (!window.is_visible_in(output)) {
            show(window, output, spec.width, spec.height);
        } else if (ctx.focused_window() == window) {
            hide(window);
        } else {
            ctx.focus(window, true);
        }
        return;
    }

    prune();
    for (pending.items) |*p| {
        if (same(p.app_id, spec.app_id) and same(p.title, spec.title)) {
            log.debug("still waiting for a scratchpad window", .{});
            return;
        }
    }

    const app_id = dupe(spec.app_id) catch return;
    const title = dupe(spec.title) catch {
        if (app_id) |p| ctx.gpa.free(p.str);
        return;
    };
    var entry: Pending = .{
        .app_id = app_id,
        .title = title,
        .width = spec.width,
        .height = spec.height,
        .since = Io.Timestamp.now(ctx.io, .awake),
    };
    pending.append(ctx.gpa, entry) catch |err| {
        log.err("append pending scratchpad failed: {}", .{ err });
        entry.deinit();
        return;
    };

    ctx.spawn(spec.argv);
}


pub fn on_new_window(window: *Window) void {
    prune();
    for (pending.items, 0..) |*p, i| {
        if (!matches(p.app_id, p.title, window)) continue;

        const output = window.output orelse ctx.current_output orelse return;
        show(window, output, p.width, p.height);

        p.deinit();
        _ = pending.orderedRemove(i);
        return;
    }
}


fn show(window: *Window, output: *Output, width: f32, height: f32) void {
    log.debug("<{*}> show scratchpad", .{ window });

    if (output.fullscreen_window()) |fullscreen| {
        if (fullscreen != window) fullscreen.prepare_unfullscreen();
    }

    window.set_output(output, true);
    window.toggle_floating(true);

    const w = fraction_of(output.exclusive_width(), width, 0.5);
    const h = fraction_of(output.exclusive_height(), height, 0.6);
    window.unbound_resize(w, h);
    window.unbound_move(@divFloor(output.exclusive_width() - w, 2), @divFloor(output.exclusive_height() - h, 2));

    window.scratchpad_hidden = false;
    window.set_tag(output.tag);
    ctx.focus(window, true);
}


fn hide(window: *Window) void {
    log.debug("<{*}> hide scratchpad", .{ window });

    window.scratchpad_hidden = true;
    if (comptime build_options.bar_enabled) {
        if (window.output) |output| output.bar.damage(.tags);
    }
}


fn find(app_id: ?Pattern, title: ?Pattern) ?*Window {
    var it = ctx.windows.safeIterator(.forward);
    while (it.next()) |window| {
        if (matches(app_id, title, window)) return window;
    }
    return null;
}


fn matches(app_id: ?Pattern, title: ?Pattern, window: *const Window) bool {
    if (app_id == null and title == null) return false;
    if (app_id) |p| if (!p.is_match(window.app_id)) return false;
    if (title) |p| if (!p.is_match(window.title)) return false;
    return true;
}


fn same(a: ?Pattern, b: ?Pattern) bool {
    const x = a orelse return b == null;
    const y = b orelse return false;
    return x.regex == y.regex and x.match_null == y.match_null and mem.eql(u8, x.str, y.str);
}


fn dupe(p: ?Pattern) !?Pattern {
    var copy = p orelse return null;
    copy.str = try ctx.gpa.dupe(u8, copy.str);
    return copy;
}


fn prune() void {
    const now = Io.Timestamp.now(ctx.io, .awake).toMilliseconds();
    var i: usize = 0;
    while (i < pending.items.len) {
        if (now - pending.items[i].since.toMilliseconds() > pending_timeout_ms) {
            pending.items[i].deinit();
            _ = pending.orderedRemove(i);
        } else i += 1;
    }
}


fn drop_pending(spec: *const Spec) void {
    var i: usize = 0;
    while (i < pending.items.len) {
        const p = &pending.items[i];
        if (same(p.app_id, spec.app_id) and same(p.title, spec.title)) {
            p.deinit();
            _ = pending.orderedRemove(i);
        } else i += 1;
    }
}


fn fraction_of(total: i32, fraction: f32, fallback: f32) i32 {
    const f = if (fraction > 0 and fraction <= 1) fraction else fallback;
    return @intFromFloat(@as(f32, @floatFromInt(total)) * f);
}
