# Family Xpense server image (one image, two Cloud Run services, D-17).
#
# Follows the Genkit Dart Cloud Run guide: AOT-compile, then copy the binary
# and the runtime files into an empty image. Two differences: the build
# context is the repository root, because server/ depends on
# ../packages/xpense_shared by path (D-05); and there is no build_runner step,
# because generated files are committed and checked by CI.
#
#   docker build -f server/Dockerfile -t xpense-server .        # from the repo root
#   docker run --rm -p 8080:8080 xpense-server                  # agent role, demo-xpense
#
# server/Dockerfile.dockerignore limits the context to server/ and the shared
# package (BuildKit reads it because it sits next to this file).

# Pinned to the toolchain in /.fvmrc (Flutter 3.50.1 ships Dart 3.14.0).
FROM dart:3.14.0 AS build

# Resolve dependencies first so the layer is cached until a pubspec changes.
WORKDIR /src
COPY packages/xpense_shared/pubspec.yaml packages/xpense_shared/
COPY server/pubspec.yaml server/pubspec.lock server/
WORKDIR /src/server
RUN dart pub get --enforce-lockfile

# Copy the sources and AOT-compile.
COPY packages/xpense_shared/ /src/packages/xpense_shared/
COPY server/ /src/server/
RUN dart pub get --offline --enforce-lockfile \
 && mkdir -p prompts /out \
 && dart compile exe bin/server.dart -o /out/server

# Minimal serving image: the binary, the system files AOT binaries need
# (libc, CA certificates, time zones) from /runtime/, and the prompt files,
# which Genkit loads from ./prompts at startup.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/bin/server
COPY --from=build /src/server/prompts/ /app/prompts/
WORKDIR /app

# Cloud Run sets PORT (8080) and the deploy sets XPENSE_ROLE and
# GOOGLE_CLOUD_PROJECT; see server/DEPLOY.md.
EXPOSE 8080
CMD ["/app/bin/server"]
