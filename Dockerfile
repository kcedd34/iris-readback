# Readback skeleton. Base image: IRIS for Health Community with AI Hub, build 154.
# Load it from the Early Access .tar and tag it first (src/ops/preflight.sh checks this).
ARG IRIS_IMAGE=irishealth-community:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
RUN mkdir -p /opt/readback /data/in /data/archive /data/work \
 && chown -R irisowner:irisowner /opt/readback /data
USER irisowner

COPY --chown=irisowner:irisowner src /opt/readback/src
COPY --chown=irisowner:irisowner tests /opt/readback/tests
COPY --chown=irisowner:irisowner data/samples /opt/readback/samples
RUN chmod +x /opt/readback/src/ops/*.sh

EXPOSE 52773 5001

# IRIS starts through iris-main; the bootstrap script runs once IRIS is up.
ENTRYPOINT ["/tini", "--", "/iris-main", "-a", "/opt/readback/src/ops/bootstrap.sh"]

HEALTHCHECK --interval=15s --timeout=30s --start-period=120s --retries=5 \
  CMD echo 'write "RB="_##class(Ens.Director).IsProductionRunning("Readback.Production"),!' | iris session IRIS -U USER 2>/dev/null | grep -q "RB=1"
