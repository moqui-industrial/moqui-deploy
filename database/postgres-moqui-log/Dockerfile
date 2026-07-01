# TimescaleDB with pgBackRest for the Moqui telemetry database.
# The latest PG18 TimescaleDB image currently available is used here.
FROM timescale/timescaledb:2.26.2-pg18

USER root
RUN apk add --no-cache pgbackrest ca-certificates curl bash

USER postgres
