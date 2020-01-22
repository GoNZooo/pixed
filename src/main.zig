const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;
const mem = std.mem;

const c = @import("./c.zig");

const ApplicationState = struct {
    tick: u64,
    running: bool,
    file_data: FileData,
    // this is meant to be a modifier for how big we need to draw pixels, as the user zooms in/out
    zoom_factor: u32,
    active_pixel: ?*Pixel = null,
    primary_color: Pixel,
    secondary_color: Pixel,
    surface: *c.SDL_Surface,
    renderer: *c.SDL_Renderer,

    pub fn handleEvent(self: *ApplicationState, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_MOUSEWHEEL => {
                if (event.wheel.y > 0) {
                    self.zoom_factor += 1;
                } else if (event.wheel.y < 0) {
                    if (self.zoom_factor > 1) {
                        self.zoom_factor -= 1;
                    } else {
                        self.zoom_factor = 1;
                    }
                }
            },
            else => {},
        }
    }

    pub fn setActivePixel(self: *ApplicationState, mouse: MouseState) void {
        const x_range = @intCast(u32, mouse.x) / self.zoom_factor;
        const y_range = @intCast(u32, mouse.y) / self.zoom_factor;
        if (x_range >= self.file_data.width or y_range >= self.file_data.height) {
            return;
        }
        const pixel_index = y_range * self.file_data.width + x_range;

        self.active_pixel = &self.file_data.pixels[pixel_index];
    }

    pub fn getMousePixel(self: ApplicationState, mouse: MouseState) ?*Pixel {
        const x_range = @intCast(u32, mouse.x) / self.zoom_factor;
        const y_range = @intCast(u32, mouse.y) / self.zoom_factor;
        if (x_range >= self.file_data.width or y_range >= self.file_data.height) {
            return null;
        }
        const pixel_index = y_range * self.file_data.width + x_range;

        return &self.file_data.pixels[pixel_index];
    }

    pub fn render(self: ApplicationState) void {
        var y: u32 = 0;
        while (y < self.file_data.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.file_data.width) : (x += 1) {
                const pixel_index = (y * self.file_data.width) + x;
                const pixel_width = self.zoom_factor;
                const pixel_height = self.zoom_factor;
                const pixel_rect = c.SDL_Rect{
                    .x = @intCast(c_int, x * pixel_width),
                    .y = @intCast(c_int, y * pixel_height),
                    .w = @intCast(c_int, pixel_width),
                    .h = @intCast(c_int, pixel_height),
                };
                const p = self.file_data.pixels[pixel_index];
                _ = c.SDL_SetRenderDrawColor(self.renderer, p.r, p.g, p.b, p.a);
                _ = c.SDL_RenderFillRect(self.renderer, &pixel_rect);
            }
        }

        self.renderSelectedColors();
    }

    fn renderSelectedColors(self: ApplicationState) void {
        const color_box_height: u32 = 10;
        const color_box_width: c_int = 20;
        const bottom_left_y = application_height - color_box_height - 1;
        const primary_color_rect = c.SDL_Rect{
            .x = 0,
            .y = bottom_left_y,
            .w = color_box_width,
            .h = color_box_height,
        };
        const inner_primary_color_rect = c.SDL_Rect{
            .x = primary_color_rect.x + 2,
            .y = primary_color_rect.y + 2,
            .w = primary_color_rect.w - 4,
            .h = primary_color_rect.h - 4,
        };
        const secondary_color_rect = c.SDL_Rect{
            .x = color_box_width + 5,
            .y = bottom_left_y,
            .w = color_box_width,
            .h = color_box_height,
        };
        const inner_secondary_color_rect = c.SDL_Rect{
            .x = secondary_color_rect.x + 2,
            .y = secondary_color_rect.y + 2,
            .w = secondary_color_rect.w - 4,
            .h = secondary_color_rect.h - 4,
        };

        _ = c.SDL_SetRenderDrawColor(self.renderer, 0x00, 0x00, 0x00, 0x00);
        _ = c.SDL_RenderDrawRect(self.renderer, &primary_color_rect);
        _ = c.SDL_RenderDrawRect(self.renderer, &secondary_color_rect);
        _ = c.SDL_SetRenderDrawColor(
            self.renderer,
            self.primary_color.r,
            self.primary_color.g,
            self.primary_color.b,
            self.primary_color.a,
        );
        _ = c.SDL_RenderFillRect(self.renderer, &inner_primary_color_rect);
        _ = c.SDL_SetRenderDrawColor(
            self.renderer,
            self.secondary_color.r,
            self.secondary_color.g,
            self.secondary_color.b,
            self.secondary_color.a,
        );
        _ = c.SDL_RenderFillRect(self.renderer, &inner_secondary_color_rect);
    }
};

const MouseState = struct {
    x: c_int,
    y: c_int,
    left_down: bool,
    middle_down: bool,
    right_down: bool,
};

const FileData = struct {
    name: []const u8,
    width: u32,
    height: u32,
    pixels: []Pixel,

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
    const init_result = c.SDL_Init(c.SDL_INIT_VIDEO);

    if (init_result < 0) {
        const error_value = c.SDL_GetError();
        debug.warn("Unable to initialize SDL: {}\n", .{error_value});
        c.exit(1);
    }

    const window = c.SDL_CreateWindow(
        "pixed",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        application_width,
        application_height,
        c.SDL_WINDOW_SHOWN,
    ) orelse return error.UnableToCreateWindow;
    const surface = c.SDL_GetWindowSurface(window) orelse return error.UnableToCreateSurface;
    const renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse return error.UnableToCreateRenderer;

    var test_pixels = try heap.page_allocator.alloc(Pixel, 16);
    mem.copy(Pixel, test_pixels, &[_]Pixel{
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
        Pixel{
            .r = 0x00,
            .g = 0x00,
            .b = 0xff,
            .a = 0xff,
        },
    });

    var application = ApplicationState{
        .tick = 0,
        .running = true,
        .zoom_factor = 10,
        .primary_color = Pixel{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff },
        .secondary_color = Pixel{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff },
        .surface = surface,
        .renderer = renderer,
        .file_data = FileData{
            .name = "test",
            .width = 4,
            .height = 4,
            .pixels = test_pixels,
        },
    };

    var keyboard: [*]const u8 = undefined;
    var event: c.SDL_Event = undefined;
    var mouse_x: c_int = undefined;
    var mouse_y: c_int = undefined;
    var previous_ticks = @intToFloat(f64, c.SDL_GetTicks());
    var start_tick: u32 = 0;
    var end_tick: u32 = 0;
    var title = try heap.page_allocator.alloc(u8, 256);
    while (application.running) : (application.tick += 1) {
        start_tick = c.SDL_GetTicks();
        if (c.SDL_PollEvent(&event) == 1) {
            application.handleEvent(event);
        }
        keyboard = c.SDL_GetKeyboardState(null);
        const mouse = getMouseState();
        update(&application, keyboard, mouse);
        render(renderer, application);
        end_tick = c.SDL_GetTicks();
        _ = try fmt.bufPrint(
            title,
            "pixed | Loop time: {} ms, Active Pixel: {}, Primary: {}, Secondary: {}\x00",
            .{
                end_tick - start_tick,
                application.active_pixel,
                application.primary_color,
                application.secondary_color,
            },
        );
        c.SDL_SetWindowTitle(window, title.ptr);
    }

    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

fn update(application: *ApplicationState, keyboard: [*]const u8, mouse: MouseState) void {
    defer application.tick += 1;
    application.setActivePixel(mouse);

    if (keyboard[c.SDL_SCANCODE_ESCAPE] == 1 or keyboard[c.SDL_SCANCODE_Q] == 1) {
        application.running = false;
    }

    if (mouse.left_down) {
        if (application.active_pixel) |active_pixel| {
            active_pixel.* = application.primary_color;
        }
    } else if (mouse.right_down) {
        if (application.active_pixel) |active_pixel| {
            active_pixel.* = application.secondary_color;
        }
    }
}

fn render(renderer: *c.SDL_Renderer, application: ApplicationState) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
    _ = c.SDL_RenderClear(renderer);

    application.render();

    _ = c.SDL_RenderPresent(renderer);
}

fn getMouseState() MouseState {
    var mouse: MouseState = undefined;
    const mouse_bitmask = c.SDL_GetMouseState(&mouse.x, &mouse.y);
    mouse.left_down = (mouse_bitmask & 0b1) == 1;
    mouse.middle_down = ((mouse_bitmask & 0b10) >> 1) == 1;
    mouse.right_down = ((mouse_bitmask & 0b100) >> 2) == 1;

    return mouse;
}

const application_width: u32 = 1280;
const application_height: u32 = 720;
