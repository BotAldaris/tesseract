const std = @import("std");
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = "tesseract";
    const gpa = b.allocator;
    var cpp_flags: std.ArrayList([]const u8) = .empty;
    try cpp_flags.append(b.allocator, "-std=gnu++20");

    const upstream = b.dependency(name, .{});

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    const lib = b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = mod,
    });

    var cpp_files: std.ArrayList([]const u8) = .empty;
    try cpp_files.appendSlice(gpa, tesseract_src_api);
    try cpp_files.appendSlice(gpa, tesseract_src_ccmain);
    try cpp_files.appendSlice(gpa, tesseract_src_ccstruct);
    try cpp_files.appendSlice(gpa, tesseract_src_ccutil);
    try cpp_files.appendSlice(gpa, tesseract_src_classify);
    try cpp_files.appendSlice(gpa, tesseract_src_ccutil);
    try cpp_files.appendSlice(gpa, tesseract_src_dict);
    try cpp_files.appendSlice(gpa, tesseract_src_lstm);
    try cpp_files.appendSlice(gpa, tesseract_src_textord);
    try cpp_files.appendSlice(gpa, tesseract_src_viewer);
    try cpp_files.appendSlice(gpa, tesseract_src_wordrec);
    try cpp_files.appendSlice(gpa, tesseract_src_arch);
    try cpp_files.appendSlice(gpa, tesseract_src_cutil);

    const disabled_legacy_engine = b.option(bool, "disabled_legacy_engine", "Disable the legacy OCR engine") orelse false;
    const graphics_disabled = b.option(bool, "graphics_disabled", "Disable disable graphics (ScrollView)") orelse false;
    const enable_lto = b.option(bool, "enable_lto", "Enable link-time optimization") orelse false;
    const fast_float = b.option(bool, "fast_float", "Enable float for LSTM") orelse true;
    const build_cli = b.option(bool, "build_cli", "Will build the tesseract cli") orelse false;
    const install_configs = b.option(bool, "tesseract_config", "Install tesseract configs") orelse false;

    if (graphics_disabled) {
        mod.addCMacro("GRAPHICS_DISABLED", "1");
    }

    if (fast_float) {
        mod.addCMacro("FAST_FLAOT", "1");
        try cpp_flags.append(gpa, "-ffast-math");
    }

    if (enable_lto) {
        try cpp_flags.append(gpa, "-flto");
    }

    if (disabled_legacy_engine) {
        for (tesseract_src_legacy) |value| {
            const index = for (cpp_files.items, 0..) |item, i| {
                if (std.mem.eql(u8, item, value))
                    break i;
            } else null;

            if (index) |i| {
                _ = cpp_files.swapRemove(i);
            }
        }
    }
    var have_neon = true;

    if (target.result.cpu.arch.isX86()) {
        have_neon = false;
        if (target.result.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx))) {
            mod.addCMacro("HAVE_AVX", "1");
            try cpp_files.appendSlice(gpa, tesseract_src_arch_avx);
            try cpp_flags.append(gpa, "-mavx");
        }
        if (target.result.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx2))) {
            mod.addCMacro("HAVE_AVX2", "1");
            try cpp_files.appendSlice(gpa, tesseract_src_arch_avx2);
            try cpp_flags.append(gpa, "-mavx2");
        }
        if (target.result.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx512f))) {
            mod.addCMacro("HAVE_AVX512F", "1");
            try cpp_flags.append(gpa, "-mavx512f");
            try cpp_files.appendSlice(gpa, tesseract_src_arch_avx512f);
        }
        if (target.result.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.fma))) {
            mod.addCMacro("HAVE_FMA", "1");
            try cpp_flags.append(gpa, "-mfma");
            try cpp_files.appendSlice(gpa, tesseract_src_arch_fma);
        }
        if (target.result.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.sse4_1))) {
            mod.addCMacro("HAVE_SSE4_1", "1");
            try cpp_flags.append(gpa, "-msse4.1");
            try cpp_files.appendSlice(gpa, tesseract_src_arch_sse41);
        }
    } else if (target.result.cpu.arch.isArm()) {
        if (!target.result.cpu.features.isEnabled(@intFromEnum(std.Target.arm.Feature.neon))) {
            have_neon = false;
        }
    } else if (target.result.cpu.arch.isAARCH64()) {} else {
        have_neon = false;
    }
    if (have_neon) {
        mod.addCMacro("HAVE_NEON", "1");
        try cpp_flags.append(gpa, "-mfpu=neon");
        try cpp_files.appendSlice(gpa, tesseract_src_arch_neon);
    }

    if (target.result.os.tag == .linux or target.result.os.tag == .macos) {
        mod.linkSystemLibrary("pthread", .{ .needed = true, .preferred_link_mode = .static });
    } else if (target.result.os.tag == .windows) {
        mod.linkSystemLibrary("ws2_32", .{ .needed = true, .preferred_link_mode = .static });
    }

    const leptonica_dep = b.dependency("leptonica", .{ .target = target, .optimize = optimize });
    mod.linkLibrary(leptonica_dep.artifact("lept"));
    const bzip_dependency = b.dependency("libarchive", .{
        .target = target,
        .optimize = optimize,
    });
    mod.linkLibrary(bzip_dependency.artifact("archive"));
    mod.addCMacro("HAVE_LIBARCHIVE", "1");

    const tiff_dep = b.dependency("tiff", .{ .target = target, .optimize = optimize });
    mod.linkLibrary(tiff_dep.artifact("tiff"));

    mod.addCMacro("HAVE_TIFFIO_H", "1");

    if (!disabled_legacy_engine) {
        try cpp_files.appendSlice(b.allocator, tesseract_src_legacy);
    }
    const config_header = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("include/tesseract/version.h.in") },
        .include_path = "tesseract/version.h",
    }, .{
        .GENERIC_MAJOR_VERSION = 5,
        .GENERIC_MINOR_VERSION = 5,
        .GENERIC_MICRO_VERSION = 3,
        .PACKAGE_VERSION = "5.5.3",
    });
    mod.addConfigHeader(config_header);

    const include_paths: []const []const u8 = &.{
        "src",
        "src/api/",
        "src/arch/",
        "src/ccmain/",
        "src/ccstruct/",
        "src/ccutil/",
        "src/classify/",
        "src/cutil/",
        "src/dict/",
        "src/lstm/",
        "src/textord/",
        "src/training/",
        "src/viewer/",
        "src/wordrec/",
        "include",
    };

    for (include_paths) |path| {
        mod.addIncludePath(upstream.path(path));
    }

    mod.addCSourceFiles(.{
        .files = cpp_files.items,
        .root = upstream.path(""),
        .flags = cpp_flags.items,
    });
    lib.installHeadersDirectory(upstream.path("include"), "", .{ .include_extensions = &.{".h"} });
    lib.installHeader(
        config_header.getOutputFile(),
        "tesseract/version.h",
    );
    b.installArtifact(lib);

    if (install_configs) {
        b.installDirectory(.{
            .source_dir = upstream.path("tessdata/configs"),
            .install_dir = .{ .custom = "share/tessdata/configs" },
            .install_subdir = "",
        });
        b.installDirectory(.{
            .source_dir = upstream.path("tessdata/tessconfigs"),
            .install_dir = .{ .custom = "share/tessdata/tessconfigs" },
            .install_subdir = "",
        });
    }

    if (build_cli) {
        const exe_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        });

        exe_mod.addCSourceFile(.{ .file = upstream.path("src/tesseract.cpp"), .flags = cpp_flags.items });
        exe_mod.addCMacro("HAVE_LIBARCHIVE", "1");
        exe_mod.addCMacro("HAVE_TIFFIO_H", "1");
        if (have_neon) {
            exe_mod.addCMacro("HAVE_NEON", "1");
        }

        exe_mod.linkLibrary(lib);
        exe_mod.linkLibrary(leptonica_dep.artifact("lept"));
        exe_mod.linkLibrary(tiff_dep.artifact("tiff"));
        exe_mod.linkLibrary(bzip_dependency.artifact("archive"));

        for (include_paths) |path| {
            exe_mod.addIncludePath(upstream.path(path));
        }
        const exe = b.addExecutable(.{
            .name = "tesseract",
            .root_module = exe_mod,
        });
        if (enable_lto) {
            exe.lto = .full;
        }

        b.installArtifact(exe);
    }
}

const tesseract_src_api: []const []const u8 = &.{
    "src/api/altorenderer.cpp",
    "src/api/baseapi.cpp",
    "src/api/capi.cpp",
    "src/api/hocrrenderer.cpp",
    "src/api/lstmboxrenderer.cpp",
    "src/api/pagerenderer.cpp",
    "src/api/pdfrenderer.cpp",
    "src/api/renderer.cpp",
    "src/api/wordstrboxrenderer.cpp",
};

const tesseract_src_arch: []const []const u8 = &.{
    "src/arch/dotproduct.cpp",
    "src/arch/simddetect.cpp",
    "src/arch/intsimdmatrix.cpp",
};

const tesseract_src_arch_avx: []const []const u8 = &.{
    "src/arch/dotproductavx.cpp",
};

const tesseract_src_arch_avx2: []const []const u8 = &.{
    "src/arch/intsimdmatrixavx2.cpp",
    "src/arch/dotproductavx.cpp",
};

const tesseract_src_arch_avx512f: []const []const u8 = &.{
    "src/arch/dotproductavx512.cpp",
};

const tesseract_src_arch_fma: []const []const u8 = &.{
    "src/arch/dotproductfma.cpp",
};

const tesseract_src_arch_sse41: []const []const u8 = &.{
    "src/arch/dotproductsse.cpp",
    "src/arch/intsimdmatrixsse.cpp",
};

const tesseract_src_arch_neon: []const []const u8 = &.{
    "src/arch/dotproductneon.cpp",
    "src/arch/intsimdmatrixneon.cpp",
};

const tesseract_src_ccmain: []const []const u8 = &.{
    "src/ccmain/adaptions.cpp",
    "src/ccmain/applybox.cpp",
    "src/ccmain/control.cpp",
    "src/ccmain/docqual.cpp",
    "src/ccmain/equationdetect.cpp",
    "src/ccmain/fixspace.cpp",
    "src/ccmain/fixxht.cpp",
    "src/ccmain/linerec.cpp",
    "src/ccmain/ltrresultiterator.cpp",
    "src/ccmain/mutableiterator.cpp",
    "src/ccmain/osdetect.cpp",
    "src/ccmain/output.cpp",
    "src/ccmain/pageiterator.cpp",
    "src/ccmain/pagesegmain.cpp",
    "src/ccmain/pagewalk.cpp",
    "src/ccmain/par_control.cpp",
    "src/ccmain/paragraphs.cpp",
    "src/ccmain/paramsd.cpp",
    "src/ccmain/pgedit.cpp",
    "src/ccmain/recogtraining.cpp",
    "src/ccmain/reject.cpp",
    "src/ccmain/resultiterator.cpp",
    "src/ccmain/superscript.cpp",
    "src/ccmain/tessbox.cpp",
    "src/ccmain/tessedit.cpp",
    "src/ccmain/tesseractclass.cpp",
    "src/ccmain/tessvars.cpp",
    "src/ccmain/tfacepp.cpp",
    "src/ccmain/thresholder.cpp",
    "src/ccmain/werdit.cpp",
};

const tesseract_src_ccstruct: []const []const u8 = &.{
    "src/ccstruct/blamer.cpp",
    "src/ccstruct/blobbox.cpp",
    "src/ccstruct/blobs.cpp",
    "src/ccstruct/blread.cpp",
    "src/ccstruct/boxread.cpp",
    "src/ccstruct/boxword.cpp",
    "src/ccstruct/coutln.cpp",
    "src/ccstruct/detlinefit.cpp",
    "src/ccstruct/dppoint.cpp",
    "src/ccstruct/fontinfo.cpp",
    "src/ccstruct/image.cpp",
    "src/ccstruct/imagedata.cpp",
    "src/ccstruct/linlsq.cpp",
    "src/ccstruct/matrix.cpp",
    "src/ccstruct/mod128.cpp",
    "src/ccstruct/normalis.cpp",
    "src/ccstruct/ocrblock.cpp",
    "src/ccstruct/ocrpara.cpp",
    "src/ccstruct/ocrrow.cpp",
    "src/ccstruct/otsuthr.cpp",
    "src/ccstruct/pageres.cpp",
    "src/ccstruct/params_training_featdef.cpp",
    "src/ccstruct/pdblock.cpp",
    "src/ccstruct/points.cpp",
    "src/ccstruct/polyblk.cpp",
    "src/ccstruct/quadlsq.cpp",
    "src/ccstruct/quspline.cpp",
    "src/ccstruct/ratngs.cpp",
    "src/ccstruct/rect.cpp",
    "src/ccstruct/rejctmap.cpp",
    "src/ccstruct/seam.cpp",
    "src/ccstruct/split.cpp",
    "src/ccstruct/statistc.cpp",
    "src/ccstruct/stepblob.cpp",
    "src/ccstruct/werd.cpp",
};

const tesseract_src_ccutil: []const []const u8 = &.{
    "src/ccutil/ambigs.cpp",
    "src/ccutil/bitvector.cpp",
    "src/ccutil/ccutil.cpp",
    "src/ccutil/errcode.cpp",
    "src/ccutil/indexmapbidi.cpp",
    "src/ccutil/params.cpp",
    "src/ccutil/scanutils.cpp",
    "src/ccutil/serialis.cpp",
    "src/ccutil/tessdatamanager.cpp",
    "src/ccutil/tprintf.cpp",
    "src/ccutil/unichar.cpp",
    "src/ccutil/unicharcompress.cpp",
    "src/ccutil/unicharmap.cpp",
    "src/ccutil/unicharset.cpp",
};

const tesseract_src_classify: []const []const u8 = &.{
    "src/classify/adaptive.cpp",
    "src/classify/adaptmatch.cpp",
    "src/classify/blobclass.cpp",
    "src/classify/classify.cpp",
    "src/classify/cluster.cpp",
    "src/classify/clusttool.cpp",
    "src/classify/cutoffs.cpp",
    "src/classify/featdefs.cpp",
    "src/classify/float2int.cpp",
    "src/classify/fpoint.cpp",
    "src/classify/intfeaturespace.cpp",
    "src/classify/intfx.cpp",
    "src/classify/intmatcher.cpp",
    "src/classify/intproto.cpp",
    "src/classify/kdtree.cpp",
    "src/classify/mfoutline.cpp",
    "src/classify/mfx.cpp",
    "src/classify/normfeat.cpp",
    "src/classify/normmatch.cpp",
    "src/classify/ocrfeatures.cpp",
    "src/classify/outfeat.cpp",
    "src/classify/picofeat.cpp",
    "src/classify/protos.cpp",
    "src/classify/shapeclassifier.cpp",
    "src/classify/shapetable.cpp",
    "src/classify/tessclassifier.cpp",
    "src/classify/trainingsample.cpp",
};

const tesseract_src_cutil: []const []const u8 = &.{
    "src/cutil/oldlist.cpp",
};

const tesseract_src_dict: []const []const u8 = &.{
    "src/dict/context.cpp",
    "src/dict/dawg.cpp",
    "src/dict/dawg_cache.cpp",
    "src/dict/dict.cpp",
    "src/dict/hyphen.cpp",
    "src/dict/permdawg.cpp",
    "src/dict/stopper.cpp",
    "src/dict/trie.cpp",
};

const tesseract_src_lstm: []const []const u8 = &.{
    "src/lstm/convolve.cpp",
    "src/lstm/fullyconnected.cpp",
    "src/lstm/functions.cpp",
    "src/lstm/input.cpp",
    "src/lstm/lstm.cpp",
    "src/lstm/lstmrecognizer.cpp",
    "src/lstm/maxpool.cpp",
    "src/lstm/network.cpp",
    "src/lstm/networkio.cpp",
    "src/lstm/parallel.cpp",
    "src/lstm/plumbing.cpp",
    "src/lstm/recodebeam.cpp",
    "src/lstm/reconfig.cpp",
    "src/lstm/reversed.cpp",
    "src/lstm/series.cpp",
    "src/lstm/stridemap.cpp",
    "src/lstm/weightmatrix.cpp",
};

const tesseract_src_textord: []const []const u8 = &.{
    "src/textord/alignedblob.cpp",
    "src/textord/baselinedetect.cpp",
    "src/textord/bbgrid.cpp",
    "src/textord/blkocc.cpp",
    "src/textord/blobgrid.cpp",
    "src/textord/ccnontextdetect.cpp",
    "src/textord/cjkpitch.cpp",
    "src/textord/colfind.cpp",
    "src/textord/colpartition.cpp",
    "src/textord/colpartitiongrid.cpp",
    "src/textord/colpartitionset.cpp",
    "src/textord/devanagari_processing.cpp",
    "src/textord/drawtord.cpp",
    "src/textord/edgblob.cpp",
    "src/textord/edgloop.cpp",
    "src/textord/equationdetectbase.cpp",
    "src/textord/fpchop.cpp",
    "src/textord/gap_map.cpp",
    "src/textord/imagefind.cpp",
    "src/textord/linefind.cpp",
    "src/textord/makerow.cpp",
    "src/textord/oldbasel.cpp",
    "src/textord/pithsync.cpp",
    "src/textord/pitsync1.cpp",
    "src/textord/scanedg.cpp",
    "src/textord/sortflts.cpp",
    "src/textord/strokewidth.cpp",
    "src/textord/tabfind.cpp",
    "src/textord/tablefind.cpp",
    "src/textord/tablerecog.cpp",
    "src/textord/tabvector.cpp",
    "src/textord/textlineprojection.cpp",
    "src/textord/textord.cpp",
    "src/textord/topitch.cpp",
    "src/textord/tordmain.cpp",
    "src/textord/tospace.cpp",
    "src/textord/tovars.cpp",
    "src/textord/underlin.cpp",
    "src/textord/wordseg.cpp",
    "src/textord/workingpartset.cpp",
};

const tesseract_src_viewer: []const []const u8 = &.{
    "src/viewer/scrollview.cpp",
    "src/viewer/svmnode.cpp",
    "src/viewer/svutil.cpp",
};

const tesseract_src_wordrec: []const []const u8 = &.{
    "src/wordrec/associate.cpp",
    "src/wordrec/chop.cpp",
    "src/wordrec/chopper.cpp",
    "src/wordrec/drawfx.cpp",
    "src/wordrec/findseam.cpp",
    "src/wordrec/gradechop.cpp",
    "src/wordrec/language_model.cpp",
    "src/wordrec/lm_consistency.cpp",
    "src/wordrec/lm_pain_points.cpp",
    "src/wordrec/lm_state.cpp",
    "src/wordrec/outlines.cpp",
    "src/wordrec/params_model.cpp",
    "src/wordrec/pieces.cpp",
    "src/wordrec/plotedges.cpp",
    "src/wordrec/render.cpp",
    "src/wordrec/segsearch.cpp",
    "src/wordrec/tface.cpp",
    "src/wordrec/wordclass.cpp",
    "src/wordrec/wordrec.cpp",
};

const tesseract_src_legacy: []const []const u8 = &.{
    "src/ccmain/adaptions.cpp",
    "src/ccmain/docqual.cpp",
    "src/ccmain/equationdetect.cpp",
    "src/ccmain/fixspace.cpp",
    "src/ccmain/fixxht.cpp",
    "src/ccmain/osdetect.cpp",
    "src/ccmain/par_control.cpp",
    "src/ccmain/recogtraining.cpp",
    "src/ccmain/superscript.cpp",
    "src/ccmain/tessbox.cpp",
    "src/ccmain/tfacepp.cpp",
    "src/ccstruct/fontinfo.cpp",
    "src/ccstruct/params_training_featdef.cpp",
    "src/ccutil/ambigs.cpp",
    "src/ccutil/bitvector.cpp",
    "src/ccutil/indexmapbidi.cpp",
    "src/classify/adaptive.cpp",
    "src/classify/adaptmatch.cpp",
    "src/classify/blobclass.cpp",
    "src/classify/cluster.cpp",
    "src/classify/clusttool.cpp",
    "src/classify/cutoffs.cpp",
    "src/classify/featdefs.cpp",
    "src/classify/float2int.cpp",
    "src/classify/fpoint.cpp",
    "src/classify/intfeaturespace.cpp",
    "src/classify/intfx.cpp",
    "src/classify/intmatcher.cpp",
    "src/classify/intproto.cpp",
    "src/classify/kdtree.cpp",
    "src/classify/mfoutline.cpp",
    "src/classify/mfx.cpp",
    "src/classify/normfeat.cpp",
    "src/classify/normmatch.cpp",
    "src/classify/ocrfeatures.cpp",
    "src/classify/outfeat.cpp",
    "src/classify/picofeat.cpp",
    "src/classify/protos.cpp",
    "src/classify/shapeclassifier.cpp",
    "src/classify/shapetable.cpp",
    "src/classify/tessclassifier.cpp",
    "src/classify/trainingsample.cpp",
    "src/dict/permdawg.cpp",
    "src/dict/hyphen.cpp",
    "src/wordrec/associate.cpp",
    "src/wordrec/chop.cpp",
    "src/wordrec/chopper.cpp",
    "src/wordrec/drawfx.cpp",
    "src/wordrec/findseam.cpp",
    "src/wordrec/gradechop.cpp",
    "src/wordrec/language_model.cpp",
    "src/wordrec/lm_consistency.cpp",
    "src/wordrec/lm_pain_points.cpp",
    "src/wordrec/lm_state.cpp",
    "src/wordrec/outlines.cpp",
    "src/wordrec/params_model.cpp",
    "src/wordrec/pieces.cpp",
    "src/wordrec/plotedges.cpp",
    "src/wordrec/render.cpp",
    "src/wordrec/segsearch.cpp",
    "src/wordrec/wordclass.cpp",
};
