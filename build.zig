const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach_glfw");
const sysaudio = @import("mach_sysaudio");
const core = @import("mach_core");

var _module: ?*std.build.Module = null;

pub fn module(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.Module {
    if (_module) |m| return m;

    const mach_core = b.dependency("mach_core", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_sysaudio = b.dependency("mach_sysaudio", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_ecs = b.dependency("mach_ecs", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_earcut = b.dependency("mach_earcut", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_basisu = b.dependency("mach_basisu", .{
        .target = target,
        .optimize = optimize,
    });

    _module = b.createModule(.{
        .source_file = .{ .path = sdkPath("/src/main.zig") },
        .dependencies = &.{
            .{ .name = "core", .module = core.module(mach_core.builder, optimize, target) },
            .{ .name = "ecs", .module = mach_ecs.module("mach-ecs") },
            .{ .name = "earcut", .module = mach_earcut.module("mach-earcut") },
            .{ .name = "sysaudio", .module = sysaudio.module(mach_sysaudio.builder, optimize, target) },
            .{ .name = "basisu", .module = mach_basisu.module("mach-basisu") },
        },
    });
    return _module.?;
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    if (target.getCpuArch() != .wasm32) {
        const tests_step = b.step("test", "Run tests");
        tests_step.dependOn(&testStep(b, optimize, target).step);
    }
}

fn testStep(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.RunStep {
    const main_tests = b.addTest(.{
        .name = "mach-tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    var iter = module(b, optimize, target).dependencies.iterator();
    while (iter.next()) |e| {
        main_tests.addModule(e.key_ptr.*, e.value_ptr.*);
    }
    b.installArtifact(main_tests);
    return b.addRunArtifact(main_tests);
}

pub const App = struct {
    b: *std.Build,
    mach_builder: *std.Build,
    name: []const u8,
    compile: *std.build.Step.Compile,
    install: *std.build.Step.InstallArtifact,
    run: *std.build.Step.Run,
    platform: core.App.Platform,
    core: core.App,

    pub fn init(
        app_builder: *std.Build,
        options: struct {
            name: []const u8,
            src: []const u8,
            target: std.zig.CrossTarget,
            optimize: std.builtin.OptimizeMode,
            custom_entrypoint: ?[]const u8 = null,
            deps: ?[]const std.build.ModuleDependency = null,
            res_dirs: ?[]const []const u8 = null,
            watch_paths: ?[]const []const u8 = null,
            mach_builder: ?*std.Build = null,
        },
    ) !App {
        const mach_builder = options.mach_builder orelse app_builder.dependency("mach", .{
            .target = options.target,
            .optimize = options.optimize,
        }).builder;
        var deps = std.ArrayList(std.build.ModuleDependency).init(app_builder.allocator);
        if (options.deps) |v| try deps.appendSlice(v);
        try deps.append(.{ .name = "mach", .module = module(mach_builder, options.optimize, options.target) });
        const mach_sysaudio = mach_builder.dependency("mach_sysaudio", .{
            .target = options.target,
            .optimize = options.optimize,
        });
        try deps.append(.{ .name = "sysaudio", .module = sysaudio.module(mach_sysaudio.builder, options.optimize, options.target) });

        const mach_core = mach_builder.dependency("mach_core", .{
            .target = options.target,
            .optimize = options.optimize,
        });
        const app = try core.App.init(app_builder, mach_core.builder, .{
            .name = options.name,
            .src = options.src,
            .target = options.target,
            .optimize = options.optimize,
            .custom_entrypoint = options.custom_entrypoint,
            .deps = deps.items,
            .res_dirs = options.res_dirs,
            .watch_paths = options.watch_paths,
        });
        return .{
            .core = app,
            .b = app.b,
            .mach_builder = mach_builder,
            .name = app.name,
            .compile = app.compile,
            .install = app.install,
            .run = app.run,
            .platform = app.platform,
        };
    }

    pub fn link(app: *const App) !void {
        sysaudio.link(app.mach_builder.dependency("mach_sysaudio", .{
            .target = app.compile.target,
            .optimize = app.compile.optimize,
        }).builder, app.compile);

        // TODO: basisu support in wasm
        if (app.platform != .web) {
            app.compile.linkLibrary(app.mach_builder.dependency("mach_basisu", .{
                .target = app.compile.target,
                .optimize = app.compile.optimize,
            }).artifact("mach-basisu"));
        }
    }
};

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

comptime {
    const min_zig = std.SemanticVersion.parse("0.11.0") catch unreachable;
    if (builtin.zig_version.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ builtin.zig_version, min_zig }));
    }
}
