ARG OPENSEARCH_VERSION=latest
FROM opensearchproject/opensearch:${OPENSEARCH_VERSION}

ARG PLUGIN_INSTALL_STRICT=true
ENV PLUGIN_INSTALL_STRICT=${PLUGIN_INSTALL_STRICT}

USER root
COPY install-opensearch-plugins.sh /usr/local/bin/install-opensearch-plugins.sh
RUN chmod +x /usr/local/bin/install-opensearch-plugins.sh \
 && /usr/local/bin/install-opensearch-plugins.sh \
 && chown -R opensearch:opensearch /usr/share/opensearch

USER opensearch
