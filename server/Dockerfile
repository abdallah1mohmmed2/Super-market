FROM dart:3.13.7-sdk AS build
WORKDIR /workspace
COPY packages/core_contracts packages/core_contracts
COPY server server
WORKDIR /workspace/server
RUN dart pub get --enforce-lockfile
RUN dart compile exe bin/server.dart -o /out/server
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
ENV APP_ENV=production HOST=0.0.0.0 PORT=8080
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/app/server"]
