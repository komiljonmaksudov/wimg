const std = @import("std");

pub fn build(b: *std.Build) void {
    // Default: wasm32-freestanding for the web target
    // Enable SIMD for faster embedding inference (supported in all modern browsers)
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{.simd128}),
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const is_wasm = target.result.cpu.arch == .wasm32;

    // Compact mode: smaller memory buffers for CF Workers (128MB limit).
    // Default (false) = web app (larger buffers). Use -Dcompact=true for MCP WASM.
    const compact = b.option(bool, "compact", "Use smaller memory buffers for CF Workers") orelse false;

    // Stub libc include path for wasm32-freestanding
    const libc_include = b.path("vendor/libc");

    // Common SQLite flags shared between native targets (iOS, macOS, etc.)
    const native_sqlite_flags: []const []const u8 = &.{
        "-DSQLITE_OMIT_LOAD_EXTENSION=1",
        "-DSQLITE_THREADSAFE=0",
        "-DSQLITE_TEMP_STORE=2",
        "-DSQLITE_OMIT_DEPRECATED=1",
        "-DSQLITE_OMIT_SHARED_CACHE=1",
        "-DSQLITE_DQS=0",
        "-DSQLITE_DEFAULT_MEMSTATUS=0",
    };

    // --- WASM library (primary target) ---
    if (is_wasm) {
        const options = b.addOptions();
        options.addOption(bool, "compact", compact);

        const wasm_lib = b.addExecutable(.{
            .name = "libwimg",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        wasm_lib.root_module.addOptions("config", options);

        // Export all `export fn` symbols
        wasm_lib.entry = .disabled;
        wasm_lib.rdynamic = true;

        const wasm_sqlite_flags: []const []const u8 = &.{
            "-DSQLITE_OS_OTHER=1",
            "-DSQLITE_OMIT_WAL=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION=1",
            "-DSQLITE_THREADSAFE=0",
            "-DSQLITE_TEMP_STORE=3",
            "-DSQLITE_OMIT_LOCALTIME=1",
            "-DSQLITE_DEFAULT_MEMSTATUS=0",
            "-DSQLITE_DEFAULT_SYNCHRONOUS=0",
            // NOT using SQLITE_OMIT_AUTOINIT — need sqlite3_open to call sqlite3_initialize/sqlite3_os_init
            "-DSQLITE_OMIT_DEPRECATED=1",
            "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
            "-DSQLITE_OMIT_SHARED_CACHE=1",
            "-DSQLITE_OMIT_UTF16=1",
            "-DSQLITE_OMIT_COMPLETE=1",
            "-DSQLITE_OMIT_DECLTYPE=1",
            "-DSQLITE_OMIT_GET_TABLE=1",
            "-DSQLITE_OMIT_TRACE=1",
            "-DSQLITE_OMIT_TCL_VARIABLE=1",
            "-DSQLITE_DQS=0",
            "-DSQLITE_CORE=1",
            "-DSQLITE_HAVE_ISNAN=1",
        };

        // Add stub libc headers for wasm32-freestanding C compilation
        wasm_lib.root_module.addIncludePath(libc_include);

        wasm_lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/sqlite3.c"),
            .flags = wasm_sqlite_flags,
        });
        // Memory budgets: compact (MCP/CF Workers) vs normal (web browser)
        //   compact: 8MB VFS + 4MB heap  = ~53MB total (fits CF Workers 128MB)
        //   normal:  32MB VFS + 16MB heap = ~149MB total (browsers handle this fine)
        const vfs_flags: []const []const u8 = if (compact)
            &.{}
        else
            &.{"-DMAX_FILE_SIZE=(32*1024*1024)"};
        const shim_flags: []const []const u8 = if (compact)
            &.{}
        else
            &.{"-DHEAP_SIZE=(16*1024*1024)"};

        wasm_lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/wasm_vfs.c"),
            .flags = vfs_flags,
        });
        wasm_lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/libc_shim.c"),
            .flags = shim_flags,
        });

        // Stack size for WASM
        wasm_lib.stack_size = 1 * 1024 * 1024; // 1 MB stack

        // Max memory: compact (MCP) = default, web = 512 MB (for embedding model ~157MB)
        if (!compact) {
            wasm_lib.max_memory = 512 * 1024 * 1024;
        }

        b.installArtifact(wasm_lib);

        // Copy wasm to wimg-web for dev (path relative to project root)
        const install_to_web = b.addInstallFile(
            wasm_lib.getEmittedBin(),
            "../../wimg-web/static/libwimg.wasm",
        );
        install_to_web.step.dependOn(&wasm_lib.step);
        b.getInstallStep().dependOn(&install_to_web.step);
    } else {
        // --- Native library (for testing / iOS / macOS / Android) ---
        const options = b.addOptions();
        options.addOption(bool, "compact", false);

        // Android needs shared library (.so) for System.loadLibrary()
        const shared = b.option(bool, "shared", "Build shared library (.so) instead of static (.a)") orelse false;

        const lib = b.addLibrary(.{
            .name = "wimg",
            .linkage = if (shared) .dynamic else .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        lib.root_module.addOptions("config", options);

        // Android: the NDK libc goes on this artifact only. The global `--libc`
        // flag also applies to the build runner on Zig 0.17, which then looks
        // for macOS libSystem inside the NDK sysroot.
        if (b.option([]const u8, "libc", "libc paths file for the target (Android NDK)")) |libc| {
            lib.setLibCFile(.{ .cwd_relative = libc });
        }

        lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/sqlite3.c"),
            .flags = native_sqlite_flags,
        });

        // Apple targets: use findNative to detect SDK via xcrun (Ghostty pattern).
        // Android: use --libc flag with NDK sysroot (see scripts/build-android.sh).
        if (target.result.os.tag.isDarwin()) {
            addAppleSdkPaths(b, lib) catch @panic("Apple SDK not found — is Xcode installed?");
        } else {
            lib.root_module.link_libc = true;
        }

        b.installArtifact(lib);

        // Install C header for Swift/JNI bridging
        b.installFile("include/libwimg.h", "include/libwimg.h");
    }

    // --- Tests ---
    const test_step = b.step("test", "Run unit tests");

    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser.zig"),
            .target = b.resolveTargetQuery(.{}), // native for tests
            .optimize = optimize,
        }),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    test_step.dependOn(&run_parser_tests.step);

    const types_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/types.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_types_tests = b.addRunArtifact(types_tests);
    test_step.dependOn(&run_types_tests.step);

    const categories_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/categories.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_categories_tests = b.addRunArtifact(categories_tests);
    test_step.dependOn(&run_categories_tests.step);

    const db_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/db.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    db_tests.root_module.addCSourceFile(.{
        .file = b.path("vendor/sqlite3.c"),
        .flags = native_sqlite_flags,
    });
    db_tests.root_module.link_libc = true;
    const run_db_tests = b.addRunArtifact(db_tests);
    test_step.dependOn(&run_db_tests.step);

    const recurring_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/recurring.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    recurring_tests.root_module.addCSourceFile(.{
        .file = b.path("vendor/sqlite3.c"),
        .flags = native_sqlite_flags,
    });
    recurring_tests.root_module.link_libc = true;
    const run_recurring_tests = b.addRunArtifact(recurring_tests);
    test_step.dependOn(&run_recurring_tests.step);

    // FinTS modules (native-only)
    const banks_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/banks.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_banks_tests = b.addRunArtifact(banks_tests);
    test_step.dependOn(&run_banks_tests.step);

    const mt940_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mt940.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_mt940_tests = b.addRunArtifact(mt940_tests);
    test_step.dependOn(&run_mt940_tests.step);

    const camt_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/camt.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_camt_tests = b.addRunArtifact(camt_tests);
    test_step.dependOn(&run_camt_tests.step);

    const fints_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fints.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    // gettimeofday (fints.zig) needs libc — implicit on Darwin, explicit on Linux CI.
    fints_tests.root_module.link_libc = true;
    const run_fints_tests = b.addRunArtifact(fints_tests);
    test_step.dependOn(&run_fints_tests.step);

    const fints_http_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fints_http.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    // getenv (fints_http.zig) needs libc — implicit on Darwin, explicit on Linux CI.
    fints_http_tests.root_module.link_libc = true;
    const run_fints_http_tests = b.addRunArtifact(fints_http_tests);
    test_step.dependOn(&run_fints_http_tests.step);

    const crypto_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/crypto.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_crypto_tests = b.addRunArtifact(crypto_tests);
    test_step.dependOn(&run_crypto_tests.step);
}

/// Detect Apple SDK via xcrun and configure include/framework/library paths.
/// Adapted from ghostty-org/ghostty pkg/apple-sdk/build.zig.
fn addAppleSdkPaths(b: *std.Build, step: *std.Build.Step.Compile) !void {
    const target_val = step.rootModuleTarget();

    const libc = try std.zig.LibCInstallation.findNative(
        b.allocator,
        b.graph.io,
        .{
            .target = &target_val,
            .environ_map = &b.graph.environ_map,
            .verbose = false,
        },
    );

    // Render libc.txt compatible with Zig's --libc flag
    var stream: std.Io.Writer.Allocating = .init(b.allocator);
    defer stream.deinit();
    try libc.render(&stream.writer);

    const wf = b.addWriteFiles();
    const path = wf.add("libc.txt", stream.written());
    step.setLibCFile(path);

    // Framework path: go up from sys_include_dir to find System/Library/Frameworks
    if (libc.sys_include_dir) |sys_include| {
        const down1 = std.fs.path.dirname(sys_include).?;
        const down2 = std.fs.path.dirname(down1).?;
        const framework_path = try std.fs.path.join(b.allocator, &.{
            down2, "System", "Library", "Frameworks",
        });
        const library_path = try std.fs.path.join(b.allocator, &.{
            down1, "lib",
        });

        step.root_module.addSystemFrameworkPath(.{ .cwd_relative = framework_path });
        step.root_module.addSystemIncludePath(.{ .cwd_relative = sys_include });
        step.root_module.addLibraryPath(.{ .cwd_relative = library_path });
    }
}
