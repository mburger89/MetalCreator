# MetalCreator's Linux test image (cross-platform spec 2.6): MetalUI's portable image plus a font.
#
# The base is MetalUI's own image (Swift 6.4, SDL 3.4 built from source, Mesa lavapipe for Vulkan on the CPU, AccessKit's
# C bindings; recipe: ../MetalUI/Backends/SDL/linux/Dockerfile), built by scripts/linux-test.sh when it is not on the machine.
# The render tests draw text with MetalUI's portable text system over the machine's installed fonts, so the image names one.
ARG BASE=metalui-portable:latest
FROM ${BASE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work/MetalCreator
