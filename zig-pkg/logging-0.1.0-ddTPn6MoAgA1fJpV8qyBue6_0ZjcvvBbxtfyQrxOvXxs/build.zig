const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 创建 logging 模块
    const logging_module = b.addModule("zig-logging", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 测试
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // 示例程序
    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    example.root_module.addImport("zig-logging", logging_module);

    const install_example = b.addInstallArtifact(example, .{});
    const example_step = b.step("example", "Build example program");
    example_step.dependOn(&install_example.step);

    const run_example = b.addRunArtifact(example);
    run_example.step.dependOn(&install_example.step);
    const run_example_step = b.step("run-example", "Run example program");
    run_example_step.dependOn(&run_example.step);

    // 简单测试程序
    const simple_test = b.addExecutable(.{
        .name = "simple_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    simple_test.root_module.addImport("zig-logging", logging_module);

    const run_simple = b.addRunArtifact(simple_test);
    const run_simple_step = b.step("run-simple", "Run simple test");
    run_simple_step.dependOn(&run_simple.step);

    // TraceTextFileSink 示例
    const trace_format = b.addExecutable(.{
        .name = "trace_format",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/trace_format.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    trace_format.root_module.addImport("zig-logging", logging_module);

    const install_trace_format = b.addInstallArtifact(trace_format, .{});
    const trace_format_step = b.step("trace-format", "Build trace format example");
    trace_format_step.dependOn(&install_trace_format.step);

    const run_trace_format = b.addRunArtifact(trace_format);
    run_trace_format.step.dependOn(&install_trace_format.step);
    const run_trace_format_step = b.step("run-trace-format", "Run trace format example");
    run_trace_format_step.dependOn(&run_trace_format.step);
}
