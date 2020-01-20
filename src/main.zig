const std = @import("std");
const debug = std.debug;

const c = @import("./c.zig");

const ApplicationState = struct {
    tick: u64,
    running: bool,
    file_data: FileData,

    pub fn handleEvent(self: *ApplicationState, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_MOUSEWHEEL => {
                if (event.wheel.y > 0) {
                    self.file_data.zoom_factor += 1;
                } else if (event.wheel.y < 0) {
                    if (self.file_data.zoom_factor > 1) {
                        self.file_data.zoom_factor -= 1;
                    } else {
                        self.file_data.zoom_factor = 1;
                    }
                }
            },
            else => {},
        }
    }

    pub fn getMousePixel(self: ApplicationState, mouse: MouseState) ?*Pixel {
        const x_range = @intCast(u32, mouse.x) / self.file_data.zoom_factor;
        const y_range = @intCast(u32, mouse.y) / self.file_data.zoom_factor;
        if (x_range >= self.file_data.width or y_range >= self.file_data.height) {
            return null;
        }
        const pixel_index = y_range * self.file_data.width + x_range;

        return &self.file_data.pixels[pixel_index];
    }
};

const MouseState = struct {
    x: c_int,
    y: c_int,
    bitmask: u32,
};

const FileData = struct {
    name: []const u8,
    width: u32,
    height: u32,
    pixels: []Pixel,
    // this is meant to be a modifier for how big we need to draw pixels, as the user zooms in/out
    zoom_factor: u32,
    surface: *c.SDL_Surface,

    pub fn draw(self: FileData) void {
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const pixel_index = (y * self.width) + x;
                const pixel_width = self.zoom_factor;
                const pixel_height = self.zoom_factor;
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
            "pixed",
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
            .zoom_factor = 10,
            .surface = surface.?,
        },
    };

    var keyboard: [*]const u8 = undefined;
    var event: c.SDL_Event = undefined;
    var mouse_x: c_int = undefined;
    var mouse_y: c_int = undefined;
    while (application.running) : (application.tick += 1) {
        if (c.SDL_PollEvent(&event) == 1) {
            application.handleEvent(event);
        }
        keyboard = c.SDL_GetKeyboardState(null);
        const bitmask = c.SDL_GetMouseState(&mouse_x, &mouse_y);
        update(&application, keyboard, MouseState{ .x = mouse_x, .y = mouse_y, .bitmask = bitmask });
        render(window.?, surface.?, application);
        _ = c.SDL_Delay(10);
    }

    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

fn update(application: *ApplicationState, keyboard: [*]const u8, mouse: MouseState) void {
    defer application.tick += 1;

    if (keyboard[c.SDL_SCANCODE_ESCAPE] == 1 or keyboard[c.SDL_SCANCODE_Q] == 1) {
        application.running = false;
    }
    const pixel = application.getMousePixel(mouse);
    debug.warn("pixel={}\n", .{pixel});
}

fn render(window: *c.SDL_Window, surface: *c.SDL_Surface, application: ApplicationState) void {
    _ = c.SDL_FillRect(surface, null, c.SDL_MapRGB(surface.format, 0xff, 0xff, 0xff));

    application.file_data.draw();

    _ = c.SDL_UpdateWindowSurface(window);
}

const application_width: u32 = 1280;
const application_height: u32 = 720;
