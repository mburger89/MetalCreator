# MetalCreator's Linux test image (cross-platform spec 2.6, xp-2 section 3): MetalUI's portable image plus OpenCascade 7.9,
# a font and the packaging tools.
#
# The base is MetalUI's own image (Swift 6.4, SDL 3.4 built from source, Mesa lavapipe for Vulkan on the CPU, AccessKit's
# C bindings; recipe: ../MetalUI/Backends/SDL/linux/Dockerfile), built by scripts/linux-test.sh when it is not on the machine.
#
# Stage `occt` builds OpenCascade from a pinned commit into /opt/occt: only the toolkits the COCCT shim links, plus the ones
# CMake resolves they need (about 4,700 compile steps; 13 minutes with 6 jobs on a loaded 10-core Mac, longer on a 4-core CI
# runner). It starts from the public Swift image, not from BASE, so its cache does not depend on MetalUI's image. It is its own
# stage so that Docker's layer cache (locally) and buildx's cache (CI, .github/workflows/xp.yml) skip it until OCCT_COMMIT,
# OCCT_JOBS or the flags change. CI builds it alone (`--target occt`) and hands the result to the final stage as OCCT_IMAGE.
#
# Stage `shadercross` builds SDL_shadercross, the compiler for the viewport's HLSL shaders (plan xp-3, user decision U1(b)), from the
# commit pinned in scripts/shadercross.env, with MetalUI's recipe (MetalUI docs/packaging.md section 4a): natively on x86_64 and aarch64,
# the DirectXShaderCompiler fork built from source (MetalUI measured 6 min 45 s at -j8 on Linux aarch64). Like `occt` it starts from the
# public Swift image and is a stage of its own, so the caches skip it until SHADERCROSS_COMMIT or SHADERCROSS_JOBS change and a new
# OpenCascade pin never rebuilds it (nor the reverse); CI builds it alone (`--target shadercross`) and hands it in as SHADERCROSS_IMAGE.
# The final stage copies /opt/shadercross; scripts/build-shaders.sh runs it through MetalUI's MetalUICompileShaders. Its shared libraries are also
# the implicit engine's run-time compiler (plan xp-c, MetalUI XP-G25), which the tests load from /opt/shadercross/lib and the tarball ships in lib/.
ARG BASE=metalui-portable:latest
ARG OCCT_IMAGE=occt
ARG SHADERCROSS_IMAGE=shadercross

FROM swift:6.4-noble AS occt
# V7_9_3 (peeled commit). A commit is pinned, not the tag: a tag can be moved.
ARG OCCT_COMMIT=a016080bf6738d6aeae020badee4e888ad1540a5
# Part of the cache key: a different value rebuilds OpenCascade. The script passes it only when OCCT_JOBS is set.
ARG OCCT_JOBS=6
RUN apt-get update && apt-get install -y --no-install-recommends git cmake ninja-build patchelf ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git init -q /tmp/occt \
    && git -C /tmp/occt fetch -q --depth 1 https://github.com/Open-Cascade-SAS/OCCT.git ${OCCT_COMMIT} \
    && git -C /tmp/occt checkout -q FETCH_HEAD
RUN cmake -S /tmp/occt -B /tmp/occt/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/occt \
         -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DBUILD_LIBRARY_TYPE=Shared \
         -DBUILD_MODULE_FoundationClasses=OFF -DBUILD_MODULE_ModelingData=OFF -DBUILD_MODULE_ModelingAlgorithms=OFF \
         -DBUILD_MODULE_Visualization=OFF -DBUILD_MODULE_ApplicationFramework=OFF -DBUILD_MODULE_DataExchange=OFF \
         -DBUILD_MODULE_Draw=OFF -DBUILD_DOC_Overview=OFF \
         "-DBUILD_ADDITIONAL_TOOLKITS=TKernel;TKMath;TKG2d;TKG3d;TKGeomBase;TKGeomAlgo;TKBRep;TKTopAlgo;TKPrim;TKBO;TKBool;TKFillet;TKOffset;TKMesh;TKShHealing;TKXSBase;TKDE;TKDESTEP;TKDESTL" \
         -DUSE_FREETYPE=OFF -DUSE_TK=OFF -DUSE_OPENGL=OFF -DUSE_GLES2=OFF -DUSE_XLIB=OFF -DUSE_TBB=OFF -DUSE_FREEIMAGE=OFF \
         -DUSE_RAPIDJSON=OFF -DUSE_DRACO=OFF -DUSE_VTK=OFF -DUSE_FFMPEG=OFF -DUSE_OPENVR=OFF \
    && cmake --build /tmp/occt/build --parallel ${OCCT_JOBS} && cmake --install /tmp/occt/build \
    && mkdir -p /opt/occt/share/licenses \
    && cp /tmp/occt/LICENSE_LGPL_21.txt /tmp/occt/OCCT_LGPL_EXCEPTION.txt /opt/occt/share/licenses/ \
    && rm -rf /tmp/occt
# OCCT's libraries carry no rpath, and an executable's RUNPATH is not searched for the libraries its libraries load, so
# libTKDESTEP could not find libTKXCAF. Each library names its own folder, which also makes /opt/occt/lib and a tarball's lib/
# work the same way.
RUN for library in /opt/occt/lib/*.so.*.*.*; do patchelf --set-rpath '$ORIGIN' "$library"; done

FROM swift:6.4-noble AS shadercross
# The value must equal scripts/shadercross.env: ShaderToolchainTests fails if they differ (CI's buildx step builds it with this default).
ARG SHADERCROSS_COMMIT=1ff05bec573988a98ef9e0260b4da44f512b8367
ARG SDL_TAG=release-3.4.16
# Part of the cache key, as OCCT_JOBS is (DirectXShaderCompiler is an LLVM build). The script passes it only when SHADERCROSS_JOBS is set.
ARG SHADERCROSS_JOBS=6
RUN apt-get update && apt-get install -y --no-install-recommends git cmake ninja-build python3 pkg-config ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# SDL3, which SDL_shadercross links, headless and into the same prefix, so the copy into the final stage carries it.
RUN git clone -q --depth 1 --branch ${SDL_TAG} https://github.com/libsdl-org/SDL.git /tmp/SDL \
    && cmake -S /tmp/SDL -B /tmp/SDL/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/shadercross \
         -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_X11=OFF -DSDL_WAYLAND=OFF \
         -DSDL_AUDIO=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    && cmake --build /tmp/SDL/build --parallel ${SHADERCROSS_JOBS} && cmake --install /tmp/SDL/build && rm -rf /tmp/SDL
# SDL_shadercross at the pinned commit (no release, no tag) with the four submodules the commit fixes (SPIRV-Cross, SPIRV-Headers,
# SPIRV-Tools and libsdl-org's DirectXShaderCompiler fork, branch 1.8.2502-SDL), vendored, with clang (gcc refuses DXC's flags).
# The fork's own DirectX-Headers submodule (d3d12shader.h) is checked out too: the first-level update does not recurse and the build stops
# at 'd3d12shader.h' file not found without it.
# -DSDLSHADERCROSS_INSTALL_RUNTIME stays OFF: it would fetch Vulkan-Loader and the Khronos headers at `main` and build vkd3d, for a
# Direct3D bytecode path the viewport does not use. The install leaves bin/shadercross with lib/libdxcompiler.so and lib/libdxil.so
# beside it (MetalUICompileShaders puts that lib first on the loader path); the commit is recorded for build-shaders.sh to check.
RUN git clone -q https://github.com/libsdl-org/SDL_shadercross.git /tmp/sc \
    && git -C /tmp/sc checkout -q ${SHADERCROSS_COMMIT} && git -C /tmp/sc submodule update --init --depth 1 \
    && git -C /tmp/sc/external/DirectXShaderCompiler submodule update --init --depth 1 external/DirectX-Headers \
    && cmake -S /tmp/sc -B /tmp/sc/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
         -DCMAKE_PREFIX_PATH=/opt/shadercross -DSDLSHADERCROSS_VENDORED=ON -DSDLSHADERCROSS_INSTALL=ON \
         -DSDLSHADERCROSS_INSTALL_RUNTIME=OFF -DSDLSHADERCROSS_CLI=ON "-DCMAKE_INSTALL_RPATH=\$ORIGIN/../lib" \
         -DSDLSHADERCROSS_SHARED=ON -DSDLSHADERCROSS_SPIRVCROSS_SHARED=ON \
    && cmake --build /tmp/sc/build --parallel ${SHADERCROSS_JOBS} && cmake --install /tmp/sc/build --prefix /opt/shadercross \
    && echo "${SHADERCROSS_COMMIT}" > /opt/shadercross/COMMIT \
    && mkdir -p /opt/shadercross/share/licenses/DirectXShaderCompiler /opt/shadercross/share/licenses/SPIRV-Cross \
         /opt/shadercross/share/licenses/SPIRV-Tools /opt/shadercross/share/licenses/SPIRV-Headers \
    && cp /tmp/sc/external/DirectXShaderCompiler/LICENSE.TXT /tmp/sc/external/DirectXShaderCompiler/ThirdPartyNotices.txt \
         /opt/shadercross/share/licenses/DirectXShaderCompiler/ \
    && cp /tmp/sc/external/SPIRV-Cross/LICENSE /opt/shadercross/share/licenses/SPIRV-Cross/ \
    && cp /tmp/sc/external/SPIRV-Tools/LICENSE /opt/shadercross/share/licenses/SPIRV-Tools/ \
    && cp /tmp/sc/external/SPIRV-Headers/LICENSE /opt/shadercross/share/licenses/SPIRV-Headers/ \
    && rm -rf /tmp/sc
# The implicit engine's run-time compiler ships these (plan xp-c task 12, MetalUI docs/packaging.md 4b); fail here naming the one that is missing.
RUN for f in lib/libSDL3_shadercross.so.0 lib/libdxcompiler.so lib/libspirv-cross-c-shared.so.0 share/licenses/SDL3_shadercross/LICENSE.txt \
             share/licenses/DirectXShaderCompiler/LICENSE.TXT share/licenses/DirectXShaderCompiler/ThirdPartyNotices.txt \
             share/licenses/SPIRV-Cross/LICENSE share/licenses/SPIRV-Tools/LICENSE share/licenses/SPIRV-Headers/LICENSE; do \
        test -s "/opt/shadercross/$f" || { echo "the shadercross stage did not leave $f" >&2; exit 1; }; done

# COPY --from takes no variable, so the stage or image to copy from is named by a FROM line.
FROM ${OCCT_IMAGE} AS occt-source
FROM ${SHADERCROSS_IMAGE} AS shadercross-source

FROM ${BASE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core patchelf desktop-file-utils file \
    && rm -rf /var/lib/apt/lists/*
COPY --from=occt-source /opt/occt /opt/occt
# SDL_shadercross for scripts/build-shaders.sh (xp-3); nothing else in the image uses it.
COPY --from=shadercross-source /opt/shadercross /opt/shadercross
# No ld.so.conf entry: the binaries must find /opt/occt/lib through the rpath Package.swift gives them, as a tarball's do.
ENV OCCT_PREFIX=/opt/occt
# patchelf and desktop-file-utils serve scripts/package-linux.sh and its checks; `file` is needed by appimagetool, which scripts/package-appimage.sh
# runs (measured: it stops with "file command is missing but required" without it). The render tests draw text with MetalUI's
# portable text system over the machine's installed fonts, so the image names one.
WORKDIR /work/MetalCreator
