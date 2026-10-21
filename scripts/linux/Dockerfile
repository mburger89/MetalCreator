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
ARG BASE=metalui-portable:latest
ARG OCCT_IMAGE=occt

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

# COPY --from takes no variable, so the stage or image to copy from is named by a FROM line.
FROM ${OCCT_IMAGE} AS occt-source

FROM ${BASE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core patchelf desktop-file-utils file \
    && rm -rf /var/lib/apt/lists/*
COPY --from=occt-source /opt/occt /opt/occt
# No ld.so.conf entry: the binaries must find /opt/occt/lib through the rpath Package.swift gives them, as a tarball's do.
ENV OCCT_PREFIX=/opt/occt
# patchelf and desktop-file-utils serve scripts/package-linux.sh and its checks; `file` is needed by appimagetool, which scripts/package-appimage.sh
# runs (measured: it stops with "file command is missing but required" without it). The render tests draw text with MetalUI's
# portable text system over the machine's installed fonts, so the image names one.
WORKDIR /work/MetalCreator
