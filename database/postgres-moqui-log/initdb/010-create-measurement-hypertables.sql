CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS public.x_f_measurement_history
(
    measurement_history_id VARCHAR(40) NOT NULL,
    measurement_type_id    VARCHAR(40),
    measurement_date       TIMESTAMP   NOT NULL,
    measurement_value      NUMERIC(26, 6),
    measurement_uom_id     VARCHAR(40),
    measurement_enum_id    VARCHAR(40),
    work_effort_id         VARCHAR(40),
    asset_id               VARCHAR(40),
    facility_id            VARCHAR(40),
    product_id             VARCHAR(40),
    reason_enum_id         VARCHAR(40),
    product_meter_id       VARCHAR(40),
    asset_maintenance_id   VARCHAR(40),
    user_id                VARCHAR(40),
    parameter_id           VARCHAR(40),
    last_updated_stamp     TIMESTAMP,
    CONSTRAINT pk_x_f_measurement_history
        PRIMARY KEY (measurement_history_id, measurement_date)
);

ALTER TABLE public.x_f_measurement_history
    OWNER TO moqui;

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_asset
    ON public.x_f_measurement_history (asset_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_measurement_date
    ON public.x_f_measurement_history (measurement_date DESC);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_asset_maintenance
    ON public.x_f_measurement_history (asset_maintenance_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_facility
    ON public.x_f_measurement_history (facility_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_measurement_type
    ON public.x_f_measurement_history (measurement_type_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_enumeration
    ON public.x_f_measurement_history (measurement_enum_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_reason_enumeration
    ON public.x_f_measurement_history (reason_enum_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_uom
    ON public.x_f_measurement_history (measurement_uom_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_parameter
    ON public.x_f_measurement_history (parameter_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_product
    ON public.x_f_measurement_history (product_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_product_meter
    ON public.x_f_measurement_history (product_meter_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_user_account
    ON public.x_f_measurement_history (user_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_history_work_effort
    ON public.x_f_measurement_history (work_effort_id);

SELECT create_hypertable(
           'public.x_f_measurement_history',
           'measurement_date',
           chunk_time_interval => INTERVAL '1 day',
           migrate_data => TRUE,
           if_not_exists => TRUE
       );

CREATE TABLE IF NOT EXISTS public.x_f_measurement_debug
(
    measurement_debug_id  VARCHAR(40) NOT NULL,
    measurement_type_id   VARCHAR(40),
    measurement_date      TIMESTAMP   NOT NULL,
    measurement_value     NUMERIC(26, 6),
    measurement_uom_id    VARCHAR(40),
    measurement_enum_id   VARCHAR(40),
    work_effort_id        VARCHAR(40),
    asset_id              VARCHAR(40),
    facility_id           VARCHAR(40),
    product_id            VARCHAR(40),
    reason_enum_id        VARCHAR(40),
    product_meter_id      VARCHAR(40),
    asset_maintenance_id  VARCHAR(40),
    user_id               VARCHAR(40),
    parameter_id          VARCHAR(40),
    last_updated_stamp    TIMESTAMP,
    CONSTRAINT pk_x_f_measurement_debug
        PRIMARY KEY (measurement_debug_id, measurement_date)
);

ALTER TABLE public.x_f_measurement_debug
    OWNER TO moqui;

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_asset
    ON public.x_f_measurement_debug (asset_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_measurement_date
    ON public.x_f_measurement_debug (measurement_date DESC);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_asset_maintenance
    ON public.x_f_measurement_debug (asset_maintenance_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_facility
    ON public.x_f_measurement_debug (facility_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_measurement_type
    ON public.x_f_measurement_debug (measurement_type_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_enumeration
    ON public.x_f_measurement_debug (measurement_enum_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_reason_enumeration
    ON public.x_f_measurement_debug (reason_enum_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_uom
    ON public.x_f_measurement_debug (measurement_uom_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_parameter
    ON public.x_f_measurement_debug (parameter_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_product
    ON public.x_f_measurement_debug (product_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_product_meter
    ON public.x_f_measurement_debug (product_meter_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_user_account
    ON public.x_f_measurement_debug (user_id);

CREATE INDEX IF NOT EXISTS idx_x_f_measurement_debug_work_effort
    ON public.x_f_measurement_debug (work_effort_id);

SELECT create_hypertable(
           'public.x_f_measurement_debug',
           'measurement_date',
           chunk_time_interval => INTERVAL '1 hour',
           migrate_data => TRUE,
           if_not_exists => TRUE
       );
