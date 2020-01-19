const std = @import("std");
const debug = std.debug;

const c = @import("./c.zig");

const ApplicationState = struct {
    tick: u64,
    running: bool,
    file_data: FileData,
};

const FileData = struct {
    name: []const u8,
    width: u32,
    height: u32,
    pixels: []Pixel,
    // this is meant to be a modifier for how big we need to draw pixels, as the user zooms in/out
    zoom_factor: f32,
    surface: *c.SDL_Surface,

    pub fn draw(self: FileData) void {
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const pixel_index = (y * self.width) + x;
                const pixel_width = application_width / self.width;
                const pixel_height = application_height / self.height;
                const pixel_rect = c.SDL_Rect{
                    .x = @intCast(c_int, x * pixel_width),
                    .y = @intCast(c_int, y * pixel_height),
                    .w = @intCast(c_int, pixel_width),
                    .h = @intCast(c_int, pixel_height),
                };
                const p = self.pixels[pixel_index];
                _ = c.SDL_FillRect(
                    self.surface,
                    &pixel_rect,
                    c.SDL_MapRGB(self.surface.format, p.r, p.g, p.b),
                );
            }
        }
    }

    // @TODO: add `saveToFile`
    // @TODO: add `loadFromFile`
};

const Pixel = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub fn main() anyerror!void {
    var window: ?*c.SDL_Window = null;
    var surface: ?*c.SDL_Surface = null;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        const error_value = c.SDL_GetError();
        debug.warn("Unable to initialize SDL: {}\n", .{error_value});
        c.exit(1);
    } else {
        window = c.SDL_CreateWindow(
            "PixEd",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            application_width,
            application_height,
            c.SDL_WINDOW_SHOWN,
        );
        if (window == null) {
            debug.warn("Unable to create window: {}\n", .{c.SDL_GetError()});
            c.exit(1);
        } else {
            surface = c.SDL_GetWindowSurface(window);
        }
    }

    var application = ApplicationState{
        .tick = 0,
        .running = true,
        .file_data = FileData{
            .name = "test",
            .width = 3,
            .height = 3,
            .pixels = &[_]Pixel{
                Pixel{
                    .r = 0xff,
                    .g = 0x00,
                    .b = 0x00,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0x00,
                    .g = 0xff,
                    .b = 0x00,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0x00,
                    .g = 0x00,
                    .b = 0xff,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0xff,
                    .g = 0xff,
                    .b = 0xff,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0x00,
                    .g = 0x00,
                    .b = 0x00,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0xa0,
                    .g = 0xa0,
                    .b = 0xa0,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0x00,
                    .g = 0x00,
                    .b = 0xff,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0x00,
                    .g = 0xff,
                    .b = 0x00,
                    .a = 0xff,
                },
                Pixel{
                    .r = 0xff,
                    .g = 0x00,
                    .b = 0x00,
                    .a = 0xff,
                },
            },
            .zoom_factor = 1.0,
            .surface = surface.?,
        },
    };

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

    application.file_data.draw();

    _ = c.SDL_UpdateWindowSurface(window);
}

const application_width: u32 = 1280;
const application_height: u32 = 720;
