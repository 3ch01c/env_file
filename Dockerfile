FROM alpine
ARG FOO="defined in Dockerfile"
RUN env
ENTRYPOINT ["sh", "-c", "env"]
