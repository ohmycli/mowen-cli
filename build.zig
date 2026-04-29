const std = @import("std");

fn readPackageVersion(b: *std.Build) std.SemanticVersion {
    const contents = std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        "build.zig.zon",
        b.allocator,
        std.Io.Limit.limited(4096),
    ) catch @panic("failed to read build.zig.zon");
    defer b.allocator.free(contents);

    const needle = ".version = \"";
    const start = std.mem.indexOf(u8, contents, needle) orelse @panic("missing .version in build.zig.zon");
    const after = start + needle.len;
    const end = std.mem.indexOfScalarPos(u8, contents, after, '"') orelse @panic("unterminated .version in build.zig.zon");
    return std.SemanticVersion.parse(contents[after..end]) catch @panic("invalid semantic version in build.zig.zon");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const package_version = readPackageVersion(b);

    // Import zig-logging dependency
    const logging_dep = b.dependency("zig-logging", .{
        .target = target,
        .optimize = optimize,
    });
    const logging_module = logging_dep.module("zig-logging");

    // Import mowen-parser dependency
    const parser_dep = b.dependency("mowen-parser", .{
        .target = target,
        .optimize = optimize,
    });
    const parser_module = parser_dep.module("mowen-parser");

    const build_options = b.addOptions();
    build_options.addOption(std.SemanticVersion, "app_version", package_version);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-logging", .module = logging_module },
            .{ .name = "mowen-parser", .module = parser_module },
        },
    });
    root_module.addOptions("build_options", build_options);

    // Create executable
    const exe = b.addExecutable(.{
        .name = "mowen-cli",
        .root_module = root_module,
        .version = package_version,
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Create modules for testing
    const config_module = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });

    const scanner_module = b.createModule(.{
        .root_source_file = b.path("src/scanner.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Config tests
    const config_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/config_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_module },
            },
        }),
    });

    // Scanner tests
    const scanner_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/scanner_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "scanner", .module = scanner_module },
            },
        }),
    });

    // Parser tests

    const run_config_tests = b.addRunArtifact(config_tests);
    const run_scanner_tests = b.addRunArtifact(scanner_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_config_tests.step);
    test_step.dependOn(&run_scanner_tests.step);

    const release_dep = b.dependency("zig-release", .{});
    const zig_release = @import("zig-release");
    zig_release.addReleaseStep(b, release_dep, .{});
}
