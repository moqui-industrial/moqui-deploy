# PostgreSQL with pgBackRest for the Moqui production database.
# The base image follows the standard Moqui PostgreSQL compose style.
FROM postgres:18.3

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

USER postgres
