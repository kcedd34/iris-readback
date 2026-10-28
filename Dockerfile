# Readback skeleton. Base image: IRIS for Health Community with AI Hub, build 154.
# Load it from the Early Access .tar and tag it first (src/ops/preflight.sh checks this).
ARG IRIS_IMAGE=irishealth-community:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
RUN mkdir -p /opt/readback /opt/readback/fastembed /data/in /data/archive /data/work \
 && chown -R irisowner:irisowner /opt/readback /data
USER irisowner

# The local embedding model is not part of the base image: the platform downloads it on first use into this
# directory. It is fetched here, at build time, so the running container needs no network (docs/probes.md Probe 8).
# This step needs network access once. If it fails, the build goes on and retrieval reports itself unavailable.
ENV FASTEMBED_CACHE_DIR=/opt/readback/fastembed
RUN (iris start IRIS quietly \
     && printf 'set emb=##class(%%AI.RAG.Embedding.FastEmbed).Create()\nhalt\n' | iris session IRIS -U USER ; \
     iris stop IRIS quietly) \
 || echo "embedding model warm-up skipped: retrieval will report itself unavailable"

COPY --chown=irisowner:irisowner src /opt/readback/src
COPY --chown=irisowner:irisowner tests /opt/readback/tests
COPY --chown=irisowner:irisowner data/samples /opt/readback/samples
COPY --chown=irisowner:irisowner data/config /opt/readback/data/config
COPY --chown=irisowner:irisowner data/replay /opt/readback/data/replay
COPY --chown=irisowner:irisowner data/policy /opt/readback/data/policy
COPY --chown=irisowner:irisowner java /opt/readback/java
RUN chmod +x /opt/readback/src/ops/*.sh /opt/readback/java/build.sh /opt/readback/tests/java/run_java_tests.sh \
 && /opt/readback/java/build.sh

EXPOSE 52773 5001

# IRIS starts through iris-main; the bootstrap script runs once IRIS is up.
ENTRYPOINT ["/tini", "--", "/iris-main", "-a", "/opt/readback/src/ops/bootstrap.sh"]

HEALTHCHECK --interval=15s --timeout=30s --start-period=120s --retries=5 \
  CMD echo 'write "RB="_##class(Ens.Director).IsProductionRunning("Readback.Production"),!' | iris session IRIS -U USER 2>/dev/null | grep -q "RB=1"
