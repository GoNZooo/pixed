const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("pixed", "src/main.zig");
    exe.setBuildMode(mode);

    exe.addIncludeDir("dependencies/SDL2-2.0.10/include");
    exe.addLibPath("dependencies/SDL2-2.0.10/lib/x64");
    exe.addIncludeDir("dependencies/SDL2_ttf-2.0.15/include");
    exe.addLibPath("dependencies/SDL2_ttf-2.0.15/lib/x64");

    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
