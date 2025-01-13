FROM ubuntu:22.04
# docker build -t ghcr.io/converged-computing/flux-service:latest .
# docker push ghcr.io/converged-computing/flux-service:latest
WORKDIR /flux-install
COPY docker/* .
RUN chmod +x /flux-install/entrypoint.sh
ENTRYPOINT ["/flux-install/entrypoint.sh"]
