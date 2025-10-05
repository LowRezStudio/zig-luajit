//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: MIT

const std = @import("std");

pub fn build(b: *std.Build) void {
    const coverage = b.option(bool, "coverage", "Generate a coverage report with kcov") orelse false;

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("luajit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib_mod.addIncludePath(b.path("include"));

    const lib = b.addLibrary(.{
        .name = "luajit",
        .linkage = .static,
        .root_module = lib_mod,
    });

    const arch_dir = if (target.result.cpu.arch == .x86) "x86" else "x64";
    lib.addLibraryPath(b.path(b.fmt("libs/windows/{s}", .{arch_dir})));
    lib.linkSystemLibrary("lua");
    lib.addIncludePath(b.path("include"));

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    if (coverage) {
        var run_test_steps: std.ArrayListUnmanaged(*std.Build.Step.Run) = .empty;
        run_test_steps.append(b.allocator, run_lib_unit_tests) catch @panic("OOM");

        const kcov_bin = b.findProgram(&.{"kcov"}, &.{}) catch "kcov";

        const merge_step = std.Build.Step.Run.create(b, "merge coverage");
        merge_step.addArgs(&.{ kcov_bin, "--merge" });
        merge_step.rename_step_with_output_arg = false;
        const merged_coverage_output = merge_step.addOutputFileArg(".");

        for (run_test_steps.items) |run_step| {
            run_step.setName(b.fmt("{s} (collect coverage)", .{run_step.step.name}));

            // prepend the kcov exec args
            const argv = run_step.argv.toOwnedSlice(b.allocator) catch @panic("OOM");
            run_step.addArgs(&.{ kcov_bin, "--collect-only" });
            run_step.addPrefixedDirectoryArg("--include-pattern=", b.path("src"));
            merge_step.addDirectoryArg(run_step.addOutputFileArg(run_step.producer.?.name));
            run_step.argv.appendSlice(b.allocator, argv) catch @panic("OOM");
        }

        const install_coverage = b.addInstallDirectory(.{
            .source_dir = merged_coverage_output,
            .install_dir = .{ .custom = "coverage" },
            .install_subdir = "",
        });
        test_step.dependOn(&install_coverage.step);
    }
}
