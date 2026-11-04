# Readback skeleton. Base image: IRIS for Health Community with AI Hub, build 154.
# Load it from the Early Access .tar and tag it first (src/ops/preflight.sh checks this).
ARG IRIS_IMAGE=irishealth-community:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
RUN mkdir -p /opt/readback /opt/readback/fastembed /data/in /data/archive /data/work \
 && chown -R irisowner:irisowner /opt/readback /data
USER irisowner

# Everything that needs the network happens here, once, at build time, so the running container needs none:
# the local embedding model (docs/probes.md Probe 8; soft, retrieval reports itself unavailable without it) and the IPM client with
# the community package workflow-rest (hard, with retries: the build fails if they do not install).
# This layer comes before the application files, so editing the source does not repeat the downloads.
ENV FASTEMBED_CACHE_DIR=/opt/readback/fastembed
COPY --chown=irisowner:irisowner src/ops/prepare-image.sh /opt/readback/prepare-image.sh
RUN chmod +x /opt/readback/prepare-image.sh && /opt/readback/prepare-image.sh

# The Java unit component changes rarely: build it before the application files so a source edit does not rebuild it.
COPY --chown=irisowner:irisowner java /opt/readback/java
RUN chmod +x /opt/readback/java/build.sh && /opt/readback/java/build.sh

# Application files, least to most often edited.
COPY --chown=irisowner:irisowner data/policy /opt/readback/data/policy
COPY --chown=irisowner:irisowner data/config /opt/readback/data/config
COPY --chown=irisowner:irisowner data/replay /opt/readback/data/replay
COPY --chown=irisowner:irisowner data/eval/report.json data/eval/ablation.json /opt/readback/data/eval/
COPY --chown=irisowner:irisowner data/samples /opt/readback/samples
COPY --chown=irisowner:irisowner tests /opt/readback/tests
COPY --chown=irisowner:irisowner src /opt/readback/src
RUN chmod +x /opt/readback/src/ops/*.sh /opt/readback/tests/java/run_java_tests.sh

EXPOSE 52773 5001

# IRIS starts through iris-main; the bootstrap script runs once IRIS is up.
ENTRYPOINT ["/tini", "--", "/iris-main", "-a", "/opt/readback/src/ops/bootstrap.sh"]

HEALTHCHECK --interval=15s --timeout=30s --start-period=120s --retries=5 \
  CMD echo 'write "RB="_##class(Ens.Director).IsProductionRunning("Readback.Production"),!' | iris session IRIS -U USER 2>/dev/null | grep -q "RB=1"
