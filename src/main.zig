const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;
const mem = std.mem;

const StringMap = std.hash_map.StringHashMap;

const c = @import("./c.zig");

const TextureSurface = struct {
    surface: *c.SDL_Surface,
    texture: *c.SDL_Texture,
};

const UiState = struct {
    hot_id: ?UiId,
    active_id: ?UiId,
    texture_surface_cache: StringMap(TextureSurface),

    /// Returns a cached version of the surface & texture for a given combination of `font` &
    /// `text`. Returning a cached version keeps will not only mean that identical buttons share
    /// information but also that we don't create & destroy resources on every render.
    pub fn getOrCreateTextureSurface(
        self: *UiState,
        renderer: *c.SDL_Renderer,
        font: *c.TTF_Font,
        text: []const u8,
    ) !TextureSurface {
        var key_buffer: [64]u8 = undefined;
        const key = try fmt.bufPrint(&key_buffer, "{}{}", .{ @ptrToInt(font), text });
        const get_result = self.texture_surface_cache.get(key);

        if (get_result) |result| {
            return result.value;
        } else {
            var texture_surface: TextureSurface = undefined;
            texture_surface.surface = c.TTF_RenderText_Solid(
                font,
                text.ptr,
                c.SDL_Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff },
            ) orelse return error.UnableToCreateButtonSurface;

            texture_surface.texture = c.SDL_CreateTextureFromSurface(
                renderer,
                texture_surface.surface,
            ) orelse return error.UnableToCreateTexture;

            _ = try self.texture_surface_cache.put(key, texture_surface);

            return texture_surface;
        }
    }
};

const UiId = struct {
    primary: PrimaryId,
    secondary: SecondaryId = 0,

    pub fn isEqual(self: UiId, id: UiId) bool {
        return mem.eql(u8, self.primary, id.primary) and self.secondary == id.secondary;
    }
};

const PrimaryId = []const u8;
const SecondaryId = u32;

fn button(
    ui: *UiState,
    renderer: *c.SDL_Renderer,
    x: c_int,
    y: c_int,
    font: *c.TTF_Font,
    text: []const u8,
    id: UiId,
    mouse: MouseState,
    keyboard: KeyboardState,
) !bool {
    const texture_surface = try ui.getOrCreateTextureSurface(renderer, font, text);
    const surface = texture_surface.surface;
    var border_rect = c.SDL_Rect{ .x = x, .y = y, .h = undefined, .w = undefined };
    const rect = c.SDL_Rect{ .x = x + 5, .y = y + 5, .h = surface.*.h, .w = surface.*.w };
    border_rect.h = rect.h + 10;
    border_rect.w = rect.w + 10;

    var result: bool = false;
    if (idsEqual(ui.active_id, id)) {
        if (mouse.left_up) {
            if (idsEqual(ui.hot_id, id) and mouse.isInside(border_rect)) {
                result = true;
            }
            ui.active_id = null;
        }
    } else if (idsEqual(ui.hot_id, id)) {
        if (mouse.left_down and mouse.isInside(border_rect)) ui.active_id = id;
    }

    if (mouse.isInside(border_rect)) {
        _ = c.SDL_SetRenderDrawColor(renderer, 0xaa, 0xaa, 0xaa, 0xff);
        _ = c.SDL_RenderFillRect(
            renderer,
            &border_rect,
        );
        ui.hot_id = id;
    } else {
        _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xff);
        _ = c.SDL_RenderDrawRect(renderer, &border_rect);
    }
    _ = c.SDL_RenderCopy(renderer, texture_surface.texture, null, &rect);

    return result;
}

fn idsEqual(a: ?UiId, b: ?UiId) bool {
    if (a == null or b == null) return false;

    return a.?.isEqual(b.?);
}

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
    info_font: *c.TTF_Font,
    selected_colors_texture: *c.SDL_Texture,
    selected_colors_width: c_int,
    selected_colors_height: c_int,
    prompt: Prompt,
    resize_x: u32,
    resize_y: u32,
    ui: UiState,
    mouse: MouseState,
    keyboard: KeyboardState,

    pub fn handleEvent(self: *ApplicationState, event: c.SDL_Event) void {
        self.mouse.left_down = false;
        self.mouse.middle_down = false;
        self.mouse.right_down = false;
        self.mouse.left_up = false;
        self.mouse.middle_up = false;
        self.mouse.right_up = false;

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
            c.SDL_MOUSEBUTTONDOWN => {
                switch (event.button.button) {
                    c.SDL_BUTTON_LEFT => {
                        self.mouse.left_down = true;
                    },
                    c.SDL_BUTTON_MIDDLE => {
                        self.mouse.middle_down = true;
                    },
                    c.SDL_BUTTON_RIGHT => {
                        self.mouse.right_down = true;
                    },
                    else => {},
                }
            },
            c.SDL_MOUSEBUTTONUP => {
                switch (event.button.button) {
                    c.SDL_BUTTON_LEFT => {
                        self.mouse.left_up = true;
                    },
                    c.SDL_BUTTON_MIDDLE => {
                        self.mouse.middle_up = true;
                    },
                    c.SDL_BUTTON_RIGHT => {
                        self.mouse.right_up = true;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    pub fn setActivePixel(self: *ApplicationState, mouse: MouseState) void {
        self.active_pixel = self.getMousePixel(mouse);
    }

    pub fn render(self: *ApplicationState) !void {
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
        self.renderPrompt();

        if (try button(
            &self.ui,
            self.renderer,
            300,
            200,
            self.info_font,
            "hey",
            UiId{ .primary = "test-button1" },
            self.mouse,
            self.keyboard,
        )) {
            debug.warn("button 1 was clicked\n", .{});
        }
        if (try button(
            &self.ui,
            self.renderer,
            300,
            250,
            self.info_font,
            "ho",
            UiId{ .primary = "test-button2" },
            self.mouse,
            self.keyboard,
        )) {
            debug.warn("button 2 was clicked\n", .{});
        }
        if (try button(
            &self.ui,
            self.renderer,
            300,
            300,
            self.info_font,
            "let's go",
            UiId{ .primary = "test-button3" },
            self.mouse,
            self.keyboard,
        )) {
            debug.warn("button 3 was clicked\n", .{});
        }

        if (try button(
            &self.ui,
            self.renderer,
            300,
            350,
            self.info_font,
            "hey",
            UiId{ .primary = "test-button4" },
            self.mouse,
            self.keyboard,
        )) {
            debug.warn("button 4 was clicked\n", .{});
        }
        if (try button(
            &self.ui,
            self.renderer,
            300,
            400,
            self.info_font,
            "ho",
            UiId{ .primary = "test-button5" },
            self.mouse,
            self.keyboard,
        )) {
            debug.warn("button 5 was clicked\n", .{});
        }
        if (try button(
            &self.ui,
            self.renderer,
            300,
            450,
            self.info_font,
            "let's go",
            UiId{ .primary = "test-button6" },
            self.mouse,
            self.keyboard,
        )) {
            debug.warn("button 6 was clicked\n", .{});
        }
    }

    pub fn updateMousePosition(self: *ApplicationState) void {
        _ = c.SDL_GetMouseState(&self.mouse.x, &self.mouse.y);
    }

    pub fn updateKeyboard(self: *ApplicationState) void {
        self.keyboard = c.SDL_GetKeyboardState(null);
    }

    fn getMousePixel(self: ApplicationState, mouse: MouseState) ?*Pixel {
        const x_range = @intCast(u32, mouse.x) / self.zoom_factor;
        const y_range = @intCast(u32, mouse.y) / self.zoom_factor;
        if (x_range >= self.file_data.width or y_range >= self.file_data.height) {
            return null;
        }
        const pixel_index = y_range * self.file_data.width + x_range;

        return &self.file_data.pixels[pixel_index];
    }

    fn renderPrompt(self: ApplicationState) void {
        switch (self.prompt) {
            .Nothing => {},
            // @TODO: create "resize" prompt
            // for inputting new dimensions
            .Resize => {},
        }
    }

    fn renderSelectedColors(self: *ApplicationState) void {
        const color_box_height: u32 = 20;
        const color_box_width: c_int = 40;
        const bottom_left_y = application_height - color_box_height - 1;
        const text_rect = c.SDL_Rect{
            .x = 2,
            .y = bottom_left_y,
            .h = self.selected_colors_height,
            .w = self.selected_colors_width,
        };
        const primary_color_rect = c.SDL_Rect{
            .x = text_rect.w + 2,
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
            .x = text_rect.w + 2 + color_box_width + 5,
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
        _ = c.SDL_RenderCopy(self.renderer, self.selected_colors_texture, null, &text_rect);
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

const Prompt = enum(u8) {
    Nothing,
    Resize,
};

const MouseState = struct {
    x: c_int,
    y: c_int,
    left_down: bool,
    middle_down: bool,
    right_down: bool,
    left_up: bool,
    middle_up: bool,
    right_up: bool,

    pub fn isInside(self: MouseState, rect: c.SDL_Rect) bool {
        // debug.warn("self.x={}\tself.y={}\n", .{ self.x, self.y });
        return self.x < rect.x + rect.w and self.x > rect.x and
            self.y < rect.y + rect.h and self.y > rect.y;
    }
};

const KeyboardState = [*]const u8;

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

    if (c.TTF_Init() == -1) {
        @panic("Unable to initialize TTF library\n");
    }

    const info_font_result = c.TTF_OpenFont("./resources/fonts/TerminusTTFWindows-4.47.0.ttf", 18);
    if (info_font_result == null) {
        const error_string: [*:0]const u8 = c.TTF_GetError();
        debug.warn("Font error: {s}\n", .{error_string});
        c.exit(1);
    }

    const selected_colors_text_surface = c.TTF_RenderText_Solid(
        info_font_result.?,
        "Colors:",
        c.SDL_Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff },
    );

    const selected_colors_texture = c.SDL_CreateTextureFromSurface(
        renderer,
        selected_colors_text_surface,
    );
    if (selected_colors_texture == null) {
        const error_string: [*:0]const u8 = c.SDL_GetError();
        debug.warn("Font texture error: {s}\n", .{error_string});
        c.exit(1);
    }

    var application = ApplicationState{
        .tick = 0,
        .running = true,
        .zoom_factor = 10,
        .primary_color = Pixel{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff },
        .secondary_color = Pixel{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff },
        .surface = surface,
        .renderer = renderer,
        .info_font = info_font_result.?,
        .selected_colors_width = selected_colors_text_surface.*.w,
        .selected_colors_height = selected_colors_text_surface.*.h,
        .selected_colors_texture = selected_colors_texture.?,
        .prompt = .Nothing,
        .resize_x = 0,
        .resize_y = 0,
        .file_data = FileData{
            .name = "test",
            .width = 4,
            .height = 4,
            .pixels = test_pixels,
        },
        .ui = UiState{
            .hot_id = null,
            .active_id = null,
            .texture_surface_cache = StringMap(TextureSurface).init(heap.page_allocator),
        },
        .mouse = undefined,
        .keyboard = undefined,
    };

    c.SDL_FreeSurface(selected_colors_text_surface);

    var event: c.SDL_Event = undefined;
    var previous_ticks = @intToFloat(f64, c.SDL_GetTicks());
    var start_tick: u32 = 0;
    var end_tick: u32 = 0;
    var title = try heap.page_allocator.alloc(u8, 256);
    while (application.running) : (application.tick += 1) {
        start_tick = c.SDL_GetTicks();
        if (c.SDL_PollEvent(&event) == 1) {
            application.handleEvent(event);
        }
        application.updateMousePosition();
        application.updateKeyboard();
        update(&application, application.keyboard, application.mouse);
        try render(renderer, &application);
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

fn render(renderer: *c.SDL_Renderer, application: *ApplicationState) !void {
    _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
    _ = c.SDL_RenderClear(renderer);

    try application.render();

    _ = c.SDL_RenderPresent(renderer);
}

const application_width: u32 = 1280;
const application_height: u32 = 720;
