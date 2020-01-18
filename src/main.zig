const std = @import("std");
const debug = std.debug;

const c = @import("./c.zig");

const ApplicationState = struct {
    tick: u64,
    running: bool,
};

pub fn main() anyerror!void {
    var window: ?*c.SDL_Window = null;
    var surface: ?*c.SDL_Surface = null;

    var application = ApplicationState{
        .tick = 0,
        .running = true,
    };

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        const error_value = c.SDL_GetError();
        debug.warn("Unable to initialize SDL: {}\n", .{error_value});
        c.exit(1);
    } else {
        window = c.SDL_CreateWindow(
            "PixEd",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            width,
            height,
            c.SDL_WINDOW_SHOWN,
        );
        if (window == null) {
            debug.warn("Unable to create window: {}\n", .{c.SDL_GetError()});
            c.exit(1);
        } else {
            surface = c.SDL_GetWindowSurface(window);
        }
    }

    var keyboard: [*]const u8 = undefined;
    while (application.running) : (application.tick += 1) {
        _ = c.SDL_PumpEvents();
        keyboard = c.SDL_GetKeyboardState(null);
        update(&application, keyboard);
        render(window.?, surface.?, application);
        _ = c.SDL_Delay(10);
    }

    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

fn update(application: *ApplicationState, keyboard: [*]const u8) void {
    defer application.tick += 1;

    if (keyboard[c.SDL_SCANCODE_ESCAPE] == 1 or keyboard[c.SDL_SCANCODE_Q] == 1) {
        application.running = false;
    }
}

fn render(window: *c.SDL_Window, surface: *c.SDL_Surface, application: ApplicationState) void {
    _ = c.SDL_FillRect(surface, null, c.SDL_MapRGB(surface.format, 0xff, 0xff, 0xff));

    _ = c.SDL_UpdateWindowSurface(window);
}

const width: u32 = 640;
const height: u32 = 480;
