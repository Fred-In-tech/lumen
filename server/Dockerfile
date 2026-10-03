# Lumen gateway image. Build from the REPOSITORY ROOT (the server depends on
# packages/lumen_core through the pub workspace):
#
#   docker build -f server/Dockerfile -t lumen-gateway .
#   docker run --rm -p 8080:8080 -e ANTHROPIC_API_KEY lumen-gateway
#
# The API key is passed at run time only; it is never baked into the image.
ARG DART_IMAGE=dart:stable
FROM ${DART_IMAGE} AS build

WORKDIR /src
# The workspace also lists the Flutter app, which needs the Flutter SDK.
# Drop it from the workspace inside the build container only.
COPY pubspec.yaml pubspec.lock ./
COPY packages/lumen_core/pubspec.yaml packages/lumen_core/
COPY server/pubspec.yaml server/
RUN sed -i '/^  - app$/d' pubspec.yaml && dart pub get

COPY packages/lumen_core/ packages/lumen_core/
COPY server/ server/
RUN dart pub get --offline \
 && dart compile exe server/bin/server.dart -o /src/out/server

# Minimal runtime: AOT binary + the Dart AOT runtime libraries.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /src/out/server /app/bin/server

ENV PORT=8080
EXPOSE 8080
USER 65534:65534
CMD ["/app/bin/server"]
