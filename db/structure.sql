SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: sync_cluster_geo_boundary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_cluster_geo_boundary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.geojson_polygon IS NOT NULL
     AND NEW.geojson_polygon->>'type' IS NOT NULL
     AND NEW.geojson_polygon->>'coordinates' IS NOT NULL THEN
    BEGIN
      NEW.geo_boundary := ST_SetSRID(ST_GeomFromGeoJSON(NEW.geojson_polygon::text), 4326);
    EXCEPTION WHEN OTHERS THEN
      NEW.geo_boundary := NULL;
    END;
  ELSE
    NEW.geo_boundary := NULL;
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: actuator_commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actuator_commands (
    id bigint NOT NULL,
    actuator_id bigint NOT NULL,
    ews_alert_id bigint,
    user_id bigint,
    command_payload text NOT NULL,
    duration_seconds integer,
    status integer DEFAULT 0,
    sent_at timestamp(6) without time zone,
    executed_at timestamp(6) without time zone,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    completed_at timestamp(6) without time zone,
    idempotency_token uuid DEFAULT gen_random_uuid() NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    expires_at timestamp(6) without time zone,
    organization_id bigint
);


--
-- Name: actuator_commands_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actuator_commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actuator_commands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actuator_commands_id_seq OWNED BY public.actuator_commands.id;


--
-- Name: actuators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actuators (
    id bigint NOT NULL,
    gateway_id bigint NOT NULL,
    name character varying,
    device_type integer,
    state integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    last_activated_at timestamp(6) without time zone,
    endpoint character varying,
    max_active_duration_s integer,
    estimated_mj_per_action numeric
);


--
-- Name: actuators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actuators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actuators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actuators_id_seq OWNED BY public.actuators.id;


--
-- Name: ai_insights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_insights (
    id bigint NOT NULL,
    insight_type integer,
    prediction_data jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    analyzable_type character varying,
    analyzable_id bigint,
    analyzed_date date,
    average_temperature numeric,
    stress_index numeric,
    total_growth_points integer,
    summary text,
    probability_score numeric,
    target_date date,
    reasoning jsonb,
    recommendation jsonb,
    fraud_detected boolean DEFAULT false NOT NULL,
    model_source character varying,
    source_log_ids bigint[] DEFAULT '{}'::bigint[]
);


--
-- Name: ai_insights_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_insights_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_insights_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_insights_id_seq OWNED BY public.ai_insights.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    action character varying NOT NULL,
    auditable_type character varying,
    auditable_id bigint,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ip_address character varying,
    user_agent character varying,
    chain_hash character varying
);


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: bio_contract_firmwares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bio_contract_firmwares (
    id bigint NOT NULL,
    version character varying,
    bytecode_payload text,
    is_active boolean,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    binary_sha256 character varying,
    target_hardware_type character varying,
    tree_family_id bigint,
    rollout_percentage integer DEFAULT 0,
    compatible_hardware_versions jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: bio_contract_firmwares_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bio_contract_firmwares_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bio_contract_firmwares_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bio_contract_firmwares_id_seq OWNED BY public.bio_contract_firmwares.id;


--
-- Name: blockchain_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blockchain_transactions (
    id bigint NOT NULL,
    wallet_id bigint,
    amount numeric,
    token_type integer,
    status integer,
    tx_hash character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    to_address character varying,
    error_message text,
    sourceable_id bigint,
    sourceable_type character varying,
    cluster_id bigint,
    locked_points integer,
    gas_price numeric,
    gas_used numeric,
    cumulative_gas_cost numeric,
    block_number bigint,
    nonce integer,
    sent_at timestamp(6) without time zone,
    confirmed_at timestamp(6) without time zone
);


--
-- Name: COLUMN blockchain_transactions.gas_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.gas_price IS 'Gas price in wei at time of transaction';


--
-- Name: COLUMN blockchain_transactions.gas_used; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.gas_used IS 'Gas units consumed by the transaction';


--
-- Name: COLUMN blockchain_transactions.cumulative_gas_cost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.cumulative_gas_cost IS 'Total gas cost in MATIC/POL (gas_price * gas_used)';


--
-- Name: COLUMN blockchain_transactions.block_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.block_number IS 'Block number where transaction was included';


--
-- Name: COLUMN blockchain_transactions.nonce; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.nonce IS 'EVM transaction nonce for idempotency';


--
-- Name: COLUMN blockchain_transactions.sent_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.sent_at IS 'Timestamp when transaction was broadcast to mempool';


--
-- Name: COLUMN blockchain_transactions.confirmed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blockchain_transactions.confirmed_at IS 'Timestamp when transaction was confirmed on-chain';


--
-- Name: blockchain_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blockchain_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blockchain_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blockchain_transactions_id_seq OWNED BY public.blockchain_transactions.id;


--
-- Name: clusters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clusters (
    id bigint NOT NULL,
    name character varying,
    region character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    geojson_polygon jsonb,
    climate_type character varying,
    organization_id bigint,
    environmental_settings jsonb,
    health_index double precision,
    active_trees_count integer DEFAULT 0 NOT NULL,
    geo_boundary public.geometry(Geometry,4326)
);


--
-- Name: clusters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clusters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clusters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clusters_id_seq OWNED BY public.clusters.id;


--
-- Name: device_calibrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_calibrations (
    id bigint NOT NULL,
    tree_id bigint NOT NULL,
    temperature_offset_c numeric,
    impedance_offset_ohms integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    vcap_coefficient numeric DEFAULT 1.0
);


--
-- Name: device_calibrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.device_calibrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: device_calibrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.device_calibrations_id_seq OWNED BY public.device_calibrations.id;


--
-- Name: ews_alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ews_alerts (
    id bigint NOT NULL,
    cluster_id bigint,
    tree_id bigint,
    severity integer,
    alert_type integer,
    message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    resolved_at timestamp(6) without time zone,
    status integer,
    resolved_by bigint,
    resolution_notes text
);


--
-- Name: ews_alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ews_alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ews_alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ews_alerts_id_seq OWNED BY public.ews_alerts.id;


--
-- Name: gateway_telemetry_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs (
    id bigint NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
)
PARTITION BY RANGE (created_at);


--
-- Name: gateway_telemetry_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gateway_telemetry_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gateway_telemetry_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gateway_telemetry_logs_id_seq OWNED BY public.gateway_telemetry_logs.id;


--
-- Name: gateway_telemetry_logs_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_default (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateway_telemetry_logs_y2026m01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_y2026m01 (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateway_telemetry_logs_y2026m02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_y2026m02 (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateway_telemetry_logs_y2026m03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_y2026m03 (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateway_telemetry_logs_y2026m04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_y2026m04 (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateway_telemetry_logs_y2026m05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_y2026m05 (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateway_telemetry_logs_y2026m06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateway_telemetry_logs_y2026m06 (
    id bigint DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass) NOT NULL,
    gateway_id bigint NOT NULL,
    queen_uid character varying,
    voltage_mv numeric,
    cellular_signal_csq integer,
    temperature_c numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gateways; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gateways (
    id bigint NOT NULL,
    uid character varying,
    ip_address character varying,
    latitude numeric,
    longitude numeric,
    altitude numeric,
    last_seen_at timestamp(6) without time zone,
    cluster_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    config_sleep_interval_s integer,
    state integer,
    firmware_version character varying,
    latest_voltage_mv integer,
    firmware_update_status integer DEFAULT 0 NOT NULL
);


--
-- Name: gateways_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gateways_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gateways_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gateways_id_seq OWNED BY public.gateways.id;


--
-- Name: hardware_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hardware_keys (
    id bigint NOT NULL,
    aes_key_hex character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    device_uid character varying,
    previous_aes_key_hex character varying,
    rotated_at timestamp(6) without time zone
);


--
-- Name: hardware_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hardware_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hardware_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hardware_keys_id_seq OWNED BY public.hardware_keys.id;


--
-- Name: identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identities (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    provider character varying,
    uid character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    access_token character varying,
    refresh_token character varying,
    auth_data jsonb,
    expires_at timestamp(6) without time zone,
    locked_at timestamp(6) without time zone,
    "primary" boolean DEFAULT false NOT NULL
);


--
-- Name: identities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identities_id_seq OWNED BY public.identities.id;


--
-- Name: maintenance_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_records (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    notes text,
    performed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    action_type integer,
    maintainable_type character varying,
    maintainable_id bigint,
    ews_alert_id bigint,
    labor_hours numeric(8,2),
    parts_cost numeric(10,2),
    hardware_verified boolean DEFAULT false NOT NULL,
    latitude numeric(10,6),
    longitude numeric(10,6)
);


--
-- Name: maintenance_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.maintenance_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: maintenance_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.maintenance_records_id_seq OWNED BY public.maintenance_records.id;


--
-- Name: naas_contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.naas_contracts (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    cluster_id bigint NOT NULL,
    total_funding numeric,
    start_date timestamp(6) without time zone,
    end_date timestamp(6) without time zone,
    status integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    emitted_tokens numeric DEFAULT 0.0,
    cancellation_terms jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp(6) without time zone
);


--
-- Name: naas_contracts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.naas_contracts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: naas_contracts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.naas_contracts_id_seq OWNED BY public.naas_contracts.id;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id bigint NOT NULL,
    name character varying,
    crypto_public_address character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    billing_email character varying,
    alert_threshold_critical_z numeric(5,2) DEFAULT 2.5,
    ai_sensitivity numeric(3,2) DEFAULT 0.7,
    data_region character varying DEFAULT 'eu-west'::character varying
);


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organizations_id_seq OWNED BY public.organizations.id;


--
-- Name: parametric_insurances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parametric_insurances (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    cluster_id bigint NOT NULL,
    status integer,
    trigger_event integer,
    payout_amount numeric,
    threshold_value numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    token_type integer DEFAULT 0 NOT NULL,
    required_confirmations integer DEFAULT 3 NOT NULL,
    paid_at timestamp(6) without time zone
);


--
-- Name: parametric_insurances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.parametric_insurances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: parametric_insurances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.parametric_insurances_id_seq OWNED BY public.parametric_insurances.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: telemetry_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs (
    id bigint NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
)
PARTITION BY RANGE (created_at);


--
-- Name: telemetry_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.telemetry_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: telemetry_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.telemetry_logs_id_seq OWNED BY public.telemetry_logs.id;


--
-- Name: telemetry_logs_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_default (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: telemetry_logs_y2026m01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_y2026m01 (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: telemetry_logs_y2026m02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_y2026m02 (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: telemetry_logs_y2026m03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_y2026m03 (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: telemetry_logs_y2026m04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_y2026m04 (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: telemetry_logs_y2026m05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_y2026m05 (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: telemetry_logs_y2026m06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_logs_y2026m06 (
    id bigint DEFAULT nextval('public.telemetry_logs_id_seq'::regclass) NOT NULL,
    acoustic_events integer,
    bio_status integer,
    created_at timestamp(6) without time zone NOT NULL,
    firmware_version_id bigint,
    growth_points numeric,
    mesh_ttl integer,
    metabolism_s integer,
    piezo_voltage_mv integer,
    queen_uid character varying,
    rssi integer,
    tamper_detected boolean,
    temperature_c numeric,
    tree_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    voltage_mv integer,
    z_value numeric,
    sap_flow numeric,
    verified_by_iotex boolean DEFAULT false NOT NULL,
    zk_proof_ref character varying
);


--
-- Name: tiny_ml_models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiny_ml_models (
    id bigint NOT NULL,
    version character varying,
    target_pest character varying,
    binary_weights_payload text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    checksum character varying,
    is_active boolean DEFAULT false,
    metadata jsonb,
    tree_family_id bigint,
    min_firmware_version character varying,
    model_format character varying,
    rollout_percentage integer DEFAULT 0,
    true_positive_rate numeric(5,4),
    false_positive_rate numeric(5,4),
    total_predictions integer DEFAULT 0 NOT NULL,
    confirmed_predictions integer DEFAULT 0 NOT NULL,
    drift_checked_at timestamp(6) without time zone
);


--
-- Name: tiny_ml_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tiny_ml_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tiny_ml_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tiny_ml_models_id_seq OWNED BY public.tiny_ml_models.id;


--
-- Name: tree_families; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tree_families (
    id bigint NOT NULL,
    name character varying,
    baseline_impedance integer,
    critical_z_min numeric,
    critical_z_max numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    biological_properties jsonb,
    scientific_name character varying,
    carbon_sequestration_coefficient double precision DEFAULT 1.0 NOT NULL,
    trees_count integer DEFAULT 0 NOT NULL
);


--
-- Name: tree_families_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tree_families_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tree_families_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tree_families_id_seq OWNED BY public.tree_families.id;


--
-- Name: trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trees (
    id bigint NOT NULL,
    did character varying,
    latitude numeric,
    longitude numeric,
    altitude numeric,
    cluster_id bigint,
    tree_family_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tiny_ml_model_id bigint,
    status integer DEFAULT 0,
    last_seen_at timestamp(6) without time zone,
    firmware_version character varying,
    latest_voltage_mv integer,
    health_streak integer DEFAULT 0 NOT NULL,
    firmware_update_status integer DEFAULT 0 NOT NULL,
    peaq_did character varying
);


--
-- Name: trees_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trees_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trees_id_seq OWNED BY public.trees.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying,
    password_digest character varying,
    role integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    organization_id bigint,
    phone_number character varying,
    last_seen_at timestamp(6) without time zone,
    first_name character varying,
    last_name character varying,
    telegram_chat_id character varying,
    push_token character varying,
    otp_required_for_login boolean DEFAULT false NOT NULL,
    recovery_codes text
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallets (
    id bigint NOT NULL,
    tree_id bigint NOT NULL,
    balance numeric,
    crypto_public_address character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    organization_id bigint,
    locked_balance numeric DEFAULT 0.0 NOT NULL
);


--
-- Name: wallets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallets_id_seq OWNED BY public.wallets.id;


--
-- Name: gateway_telemetry_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_default DEFAULT;


--
-- Name: gateway_telemetry_logs_y2026m01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_y2026m01 FOR VALUES FROM ('2026-01-01 00:00:00') TO ('2026-02-01 00:00:00');


--
-- Name: gateway_telemetry_logs_y2026m02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_y2026m02 FOR VALUES FROM ('2026-02-01 00:00:00') TO ('2026-03-01 00:00:00');


--
-- Name: gateway_telemetry_logs_y2026m03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_y2026m03 FOR VALUES FROM ('2026-03-01 00:00:00') TO ('2026-04-01 00:00:00');


--
-- Name: gateway_telemetry_logs_y2026m04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_y2026m04 FOR VALUES FROM ('2026-04-01 00:00:00') TO ('2026-05-01 00:00:00');


--
-- Name: gateway_telemetry_logs_y2026m05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_y2026m05 FOR VALUES FROM ('2026-05-01 00:00:00') TO ('2026-06-01 00:00:00');


--
-- Name: gateway_telemetry_logs_y2026m06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ATTACH PARTITION public.gateway_telemetry_logs_y2026m06 FOR VALUES FROM ('2026-06-01 00:00:00') TO ('2026-07-01 00:00:00');


--
-- Name: telemetry_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_default DEFAULT;


--
-- Name: telemetry_logs_y2026m01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_y2026m01 FOR VALUES FROM ('2026-01-01 00:00:00') TO ('2026-02-01 00:00:00');


--
-- Name: telemetry_logs_y2026m02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_y2026m02 FOR VALUES FROM ('2026-02-01 00:00:00') TO ('2026-03-01 00:00:00');


--
-- Name: telemetry_logs_y2026m03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_y2026m03 FOR VALUES FROM ('2026-03-01 00:00:00') TO ('2026-04-01 00:00:00');


--
-- Name: telemetry_logs_y2026m04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_y2026m04 FOR VALUES FROM ('2026-04-01 00:00:00') TO ('2026-05-01 00:00:00');


--
-- Name: telemetry_logs_y2026m05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_y2026m05 FOR VALUES FROM ('2026-05-01 00:00:00') TO ('2026-06-01 00:00:00');


--
-- Name: telemetry_logs_y2026m06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ATTACH PARTITION public.telemetry_logs_y2026m06 FOR VALUES FROM ('2026-06-01 00:00:00') TO ('2026-07-01 00:00:00');


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: actuator_commands id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuator_commands ALTER COLUMN id SET DEFAULT nextval('public.actuator_commands_id_seq'::regclass);


--
-- Name: actuators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuators ALTER COLUMN id SET DEFAULT nextval('public.actuators_id_seq'::regclass);


--
-- Name: ai_insights id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_insights ALTER COLUMN id SET DEFAULT nextval('public.ai_insights_id_seq'::regclass);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: bio_contract_firmwares id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bio_contract_firmwares ALTER COLUMN id SET DEFAULT nextval('public.bio_contract_firmwares_id_seq'::regclass);


--
-- Name: blockchain_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_transactions ALTER COLUMN id SET DEFAULT nextval('public.blockchain_transactions_id_seq'::regclass);


--
-- Name: clusters id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clusters ALTER COLUMN id SET DEFAULT nextval('public.clusters_id_seq'::regclass);


--
-- Name: device_calibrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_calibrations ALTER COLUMN id SET DEFAULT nextval('public.device_calibrations_id_seq'::regclass);


--
-- Name: ews_alerts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ews_alerts ALTER COLUMN id SET DEFAULT nextval('public.ews_alerts_id_seq'::regclass);


--
-- Name: gateway_telemetry_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs ALTER COLUMN id SET DEFAULT nextval('public.gateway_telemetry_logs_id_seq'::regclass);


--
-- Name: gateways id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateways ALTER COLUMN id SET DEFAULT nextval('public.gateways_id_seq'::regclass);


--
-- Name: hardware_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hardware_keys ALTER COLUMN id SET DEFAULT nextval('public.hardware_keys_id_seq'::regclass);


--
-- Name: identities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities ALTER COLUMN id SET DEFAULT nextval('public.identities_id_seq'::regclass);


--
-- Name: maintenance_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_records ALTER COLUMN id SET DEFAULT nextval('public.maintenance_records_id_seq'::regclass);


--
-- Name: naas_contracts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.naas_contracts ALTER COLUMN id SET DEFAULT nextval('public.naas_contracts_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations ALTER COLUMN id SET DEFAULT nextval('public.organizations_id_seq'::regclass);


--
-- Name: parametric_insurances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametric_insurances ALTER COLUMN id SET DEFAULT nextval('public.parametric_insurances_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: telemetry_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs ALTER COLUMN id SET DEFAULT nextval('public.telemetry_logs_id_seq'::regclass);


--
-- Name: tiny_ml_models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiny_ml_models ALTER COLUMN id SET DEFAULT nextval('public.tiny_ml_models_id_seq'::regclass);


--
-- Name: tree_families id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_families ALTER COLUMN id SET DEFAULT nextval('public.tree_families_id_seq'::regclass);


--
-- Name: trees id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees ALTER COLUMN id SET DEFAULT nextval('public.trees_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: wallets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets ALTER COLUMN id SET DEFAULT nextval('public.wallets_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: actuator_commands actuator_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuator_commands
    ADD CONSTRAINT actuator_commands_pkey PRIMARY KEY (id);


--
-- Name: actuators actuators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuators
    ADD CONSTRAINT actuators_pkey PRIMARY KEY (id);


--
-- Name: ai_insights ai_insights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_insights
    ADD CONSTRAINT ai_insights_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: bio_contract_firmwares bio_contract_firmwares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bio_contract_firmwares
    ADD CONSTRAINT bio_contract_firmwares_pkey PRIMARY KEY (id);


--
-- Name: blockchain_transactions blockchain_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_transactions
    ADD CONSTRAINT blockchain_transactions_pkey PRIMARY KEY (id);


--
-- Name: clusters clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clusters
    ADD CONSTRAINT clusters_pkey PRIMARY KEY (id);


--
-- Name: device_calibrations device_calibrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_calibrations
    ADD CONSTRAINT device_calibrations_pkey PRIMARY KEY (id);


--
-- Name: ews_alerts ews_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ews_alerts
    ADD CONSTRAINT ews_alerts_pkey PRIMARY KEY (id);


--
-- Name: gateway_telemetry_logs gateway_telemetry_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs
    ADD CONSTRAINT gateway_telemetry_logs_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_default gateway_telemetry_logs_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_default
    ADD CONSTRAINT gateway_telemetry_logs_default_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_y2026m01 gateway_telemetry_logs_y2026m01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_y2026m01
    ADD CONSTRAINT gateway_telemetry_logs_y2026m01_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_y2026m02 gateway_telemetry_logs_y2026m02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_y2026m02
    ADD CONSTRAINT gateway_telemetry_logs_y2026m02_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_y2026m03 gateway_telemetry_logs_y2026m03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_y2026m03
    ADD CONSTRAINT gateway_telemetry_logs_y2026m03_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_y2026m04 gateway_telemetry_logs_y2026m04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_y2026m04
    ADD CONSTRAINT gateway_telemetry_logs_y2026m04_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_y2026m05 gateway_telemetry_logs_y2026m05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_y2026m05
    ADD CONSTRAINT gateway_telemetry_logs_y2026m05_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateway_telemetry_logs_y2026m06 gateway_telemetry_logs_y2026m06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateway_telemetry_logs_y2026m06
    ADD CONSTRAINT gateway_telemetry_logs_y2026m06_pkey PRIMARY KEY (id, created_at);


--
-- Name: gateways gateways_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateways
    ADD CONSTRAINT gateways_pkey PRIMARY KEY (id);


--
-- Name: hardware_keys hardware_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hardware_keys
    ADD CONSTRAINT hardware_keys_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: maintenance_records maintenance_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_records
    ADD CONSTRAINT maintenance_records_pkey PRIMARY KEY (id);


--
-- Name: naas_contracts naas_contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.naas_contracts
    ADD CONSTRAINT naas_contracts_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: parametric_insurances parametric_insurances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametric_insurances
    ADD CONSTRAINT parametric_insurances_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: telemetry_logs telemetry_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs
    ADD CONSTRAINT telemetry_logs_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_default telemetry_logs_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_default
    ADD CONSTRAINT telemetry_logs_default_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_y2026m01 telemetry_logs_y2026m01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_y2026m01
    ADD CONSTRAINT telemetry_logs_y2026m01_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_y2026m02 telemetry_logs_y2026m02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_y2026m02
    ADD CONSTRAINT telemetry_logs_y2026m02_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_y2026m03 telemetry_logs_y2026m03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_y2026m03
    ADD CONSTRAINT telemetry_logs_y2026m03_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_y2026m04 telemetry_logs_y2026m04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_y2026m04
    ADD CONSTRAINT telemetry_logs_y2026m04_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_y2026m05 telemetry_logs_y2026m05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_y2026m05
    ADD CONSTRAINT telemetry_logs_y2026m05_pkey PRIMARY KEY (id, created_at);


--
-- Name: telemetry_logs_y2026m06 telemetry_logs_y2026m06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_logs_y2026m06
    ADD CONSTRAINT telemetry_logs_y2026m06_pkey PRIMARY KEY (id, created_at);


--
-- Name: tiny_ml_models tiny_ml_models_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiny_ml_models
    ADD CONSTRAINT tiny_ml_models_pkey PRIMARY KEY (id);


--
-- Name: tree_families tree_families_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_families
    ADD CONSTRAINT tree_families_pkey PRIMARY KEY (id);


--
-- Name: trees trees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees
    ADD CONSTRAINT trees_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: index_gateway_telemetry_logs_on_gateway_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_gateway_telemetry_logs_on_gateway_id ON ONLY public.gateway_telemetry_logs USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_default_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_default_gateway_id_idx ON public.gateway_telemetry_logs_default USING btree (gateway_id);


--
-- Name: idx_gateway_telemetry_logs_queen_uid_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gateway_telemetry_logs_queen_uid_created ON ONLY public.gateway_telemetry_logs USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_default_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_default_queen_uid_created_at_idx ON public.gateway_telemetry_logs_default USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_y2026m01_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m01_gateway_id_idx ON public.gateway_telemetry_logs_y2026m01 USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_y2026m01_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m01_queen_uid_created_at_idx ON public.gateway_telemetry_logs_y2026m01 USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_y2026m02_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m02_gateway_id_idx ON public.gateway_telemetry_logs_y2026m02 USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_y2026m02_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m02_queen_uid_created_at_idx ON public.gateway_telemetry_logs_y2026m02 USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_y2026m03_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m03_gateway_id_idx ON public.gateway_telemetry_logs_y2026m03 USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_y2026m03_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m03_queen_uid_created_at_idx ON public.gateway_telemetry_logs_y2026m03 USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_y2026m04_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m04_gateway_id_idx ON public.gateway_telemetry_logs_y2026m04 USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_y2026m04_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m04_queen_uid_created_at_idx ON public.gateway_telemetry_logs_y2026m04 USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_y2026m05_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m05_gateway_id_idx ON public.gateway_telemetry_logs_y2026m05 USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_y2026m05_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m05_queen_uid_created_at_idx ON public.gateway_telemetry_logs_y2026m05 USING btree (queen_uid, created_at);


--
-- Name: gateway_telemetry_logs_y2026m06_gateway_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m06_gateway_id_idx ON public.gateway_telemetry_logs_y2026m06 USING btree (gateway_id);


--
-- Name: gateway_telemetry_logs_y2026m06_queen_uid_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gateway_telemetry_logs_y2026m06_queen_uid_created_at_idx ON public.gateway_telemetry_logs_y2026m06 USING btree (queen_uid, created_at);


--
-- Name: idx_ai_insights_reasoning_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_insights_reasoning_gin ON public.ai_insights USING gin (reasoning);


--
-- Name: idx_ai_insights_target_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_insights_target_date ON public.ai_insights USING btree (target_date);


--
-- Name: idx_ai_insights_unique_report; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ai_insights_unique_report ON public.ai_insights USING btree (analyzable_type, analyzable_id, target_date, insight_type, model_source);


--
-- Name: idx_telemetry_logs_bio_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_telemetry_logs_bio_status_created ON ONLY public.telemetry_logs USING btree (bio_status, created_at);


--
-- Name: idx_telemetry_logs_piezo_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_telemetry_logs_piezo_created ON ONLY public.telemetry_logs USING btree (piezo_voltage_mv, created_at);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_actuator_commands_on_actuator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuator_commands_on_actuator_id ON public.actuator_commands USING btree (actuator_id);


--
-- Name: index_actuator_commands_on_ews_alert_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuator_commands_on_ews_alert_id ON public.actuator_commands USING btree (ews_alert_id);


--
-- Name: index_actuator_commands_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuator_commands_on_expires_at ON public.actuator_commands USING btree (expires_at) WHERE (status = ANY (ARRAY[0, 1]));


--
-- Name: index_actuator_commands_on_idempotency_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_actuator_commands_on_idempotency_token ON public.actuator_commands USING btree (idempotency_token);


--
-- Name: index_actuator_commands_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuator_commands_on_organization_id ON public.actuator_commands USING btree (organization_id);


--
-- Name: index_actuator_commands_on_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuator_commands_on_priority ON public.actuator_commands USING btree (priority);


--
-- Name: index_actuator_commands_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuator_commands_on_user_id ON public.actuator_commands USING btree (user_id);


--
-- Name: index_actuators_on_gateway_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actuators_on_gateway_id ON public.actuators USING btree (gateway_id);


--
-- Name: index_ai_insights_on_analyzable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_insights_on_analyzable ON public.ai_insights USING btree (analyzable_type, analyzable_id);


--
-- Name: index_ai_insights_on_source_log_ids; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_insights_on_source_log_ids ON public.ai_insights USING gin (source_log_ids);


--
-- Name: index_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_action ON public.audit_logs USING btree (action);


--
-- Name: index_audit_logs_on_auditable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_auditable ON public.audit_logs USING btree (auditable_type, auditable_id);


--
-- Name: index_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_created_at ON public.audit_logs USING btree (created_at DESC);


--
-- Name: index_audit_logs_on_ip_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_ip_address ON public.audit_logs USING btree (ip_address) WHERE (ip_address IS NOT NULL);


--
-- Name: index_audit_logs_on_org_and_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_org_and_created ON public.audit_logs USING btree (organization_id, created_at DESC);


--
-- Name: index_audit_logs_on_org_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_org_id_and_id ON public.audit_logs USING btree (organization_id, id DESC);


--
-- Name: index_audit_logs_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_organization_id ON public.audit_logs USING btree (organization_id);


--
-- Name: index_audit_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: index_bio_contract_firmwares_on_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bio_contract_firmwares_on_is_active ON public.bio_contract_firmwares USING btree (is_active) WHERE (is_active = true);


--
-- Name: index_bio_contract_firmwares_on_tree_family_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bio_contract_firmwares_on_tree_family_id ON public.bio_contract_firmwares USING btree (tree_family_id);


--
-- Name: index_blockchain_transactions_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blockchain_transactions_on_block_number ON public.blockchain_transactions USING btree (block_number);


--
-- Name: index_blockchain_transactions_on_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blockchain_transactions_on_cluster_id ON public.blockchain_transactions USING btree (cluster_id);


--
-- Name: index_blockchain_transactions_on_confirmed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blockchain_transactions_on_confirmed_at ON public.blockchain_transactions USING btree (confirmed_at);


--
-- Name: index_blockchain_transactions_on_sourceable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blockchain_transactions_on_sourceable ON public.blockchain_transactions USING btree (sourceable_type, sourceable_id);


--
-- Name: index_blockchain_transactions_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blockchain_transactions_on_wallet_id ON public.blockchain_transactions USING btree (wallet_id);


--
-- Name: index_blockchain_transactions_on_wallet_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blockchain_transactions_on_wallet_id_and_status ON public.blockchain_transactions USING btree (wallet_id, status);


--
-- Name: index_clusters_on_geo_boundary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_clusters_on_geo_boundary ON public.clusters USING gist (geo_boundary);


--
-- Name: index_clusters_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_clusters_on_organization_id ON public.clusters USING btree (organization_id);


--
-- Name: index_device_calibrations_on_tree_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_calibrations_on_tree_id ON public.device_calibrations USING btree (tree_id);


--
-- Name: index_ews_alerts_on_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ews_alerts_on_cluster_id ON public.ews_alerts USING btree (cluster_id);


--
-- Name: index_ews_alerts_on_cluster_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ews_alerts_on_cluster_id_and_status ON public.ews_alerts USING btree (cluster_id, status);


--
-- Name: index_ews_alerts_on_resolved_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ews_alerts_on_resolved_at ON public.ews_alerts USING btree (resolved_at);


--
-- Name: index_ews_alerts_on_tree_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ews_alerts_on_tree_id ON public.ews_alerts USING btree (tree_id);


--
-- Name: index_ews_alerts_unique_active_per_tree; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ews_alerts_unique_active_per_tree ON public.ews_alerts USING btree (tree_id, alert_type, status) WHERE ((status = 0) AND (tree_id IS NOT NULL));


--
-- Name: index_gateways_on_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_gateways_on_cluster_id ON public.gateways USING btree (cluster_id);


--
-- Name: index_gateways_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_gateways_on_uid ON public.gateways USING btree (uid);


--
-- Name: index_hardware_keys_on_device_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_hardware_keys_on_device_uid ON public.hardware_keys USING btree (device_uid);


--
-- Name: index_identities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identities_on_user_id ON public.identities USING btree (user_id);


--
-- Name: index_maintenance_records_on_action_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_records_on_action_type ON public.maintenance_records USING btree (action_type);


--
-- Name: index_maintenance_records_on_ews_alert_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_records_on_ews_alert_id ON public.maintenance_records USING btree (ews_alert_id);


--
-- Name: index_maintenance_records_on_hardware_verified; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_records_on_hardware_verified ON public.maintenance_records USING btree (hardware_verified);


--
-- Name: index_maintenance_records_on_maintainable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_records_on_maintainable ON public.maintenance_records USING btree (maintainable_type, maintainable_id);


--
-- Name: index_maintenance_records_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_records_on_user_id ON public.maintenance_records USING btree (user_id);


--
-- Name: index_naas_contracts_on_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_naas_contracts_on_cluster_id ON public.naas_contracts USING btree (cluster_id);


--
-- Name: index_naas_contracts_on_cluster_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_naas_contracts_on_cluster_id_and_status ON public.naas_contracts USING btree (cluster_id, status);


--
-- Name: index_naas_contracts_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_naas_contracts_on_organization_id ON public.naas_contracts USING btree (organization_id);


--
-- Name: index_parametric_insurances_on_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parametric_insurances_on_cluster_id ON public.parametric_insurances USING btree (cluster_id);


--
-- Name: index_parametric_insurances_on_cluster_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parametric_insurances_on_cluster_id_and_status ON public.parametric_insurances USING btree (cluster_id, status);


--
-- Name: index_parametric_insurances_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parametric_insurances_on_organization_id ON public.parametric_insurances USING btree (organization_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_telemetry_logs_on_tree_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_logs_on_tree_id ON ONLY public.telemetry_logs USING btree (tree_id);


--
-- Name: index_telemetry_logs_on_tree_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_logs_on_tree_id_and_created_at ON ONLY public.telemetry_logs USING btree (tree_id, created_at);


--
-- Name: index_tiny_ml_models_on_tree_family_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tiny_ml_models_on_tree_family_id ON public.tiny_ml_models USING btree (tree_family_id);


--
-- Name: index_tree_families_on_scientific_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tree_families_on_scientific_name ON public.tree_families USING btree (scientific_name) WHERE (scientific_name IS NOT NULL);


--
-- Name: index_trees_on_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trees_on_cluster_id ON public.trees USING btree (cluster_id);


--
-- Name: index_trees_on_cluster_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trees_on_cluster_id_and_status ON public.trees USING btree (cluster_id, status);


--
-- Name: index_trees_on_did; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trees_on_did ON public.trees USING btree (did);


--
-- Name: index_trees_on_peaq_did; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trees_on_peaq_did ON public.trees USING btree (peaq_did);


--
-- Name: index_trees_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trees_on_status ON public.trees USING btree (status);


--
-- Name: index_trees_on_tiny_ml_model_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trees_on_tiny_ml_model_id ON public.trees USING btree (tiny_ml_model_id);


--
-- Name: index_trees_on_tree_family_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trees_on_tree_family_id ON public.trees USING btree (tree_family_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: index_users_on_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_seen_at ON public.users USING btree (last_seen_at);


--
-- Name: index_users_on_org_last_seen_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_org_last_seen_id ON public.users USING btree (organization_id, last_seen_at DESC, id DESC);


--
-- Name: index_users_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_organization_id ON public.users USING btree (organization_id);


--
-- Name: index_wallets_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_organization_id ON public.wallets USING btree (organization_id);


--
-- Name: index_wallets_on_organization_id_and_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_organization_id_and_balance ON public.wallets USING btree (organization_id, balance);


--
-- Name: index_wallets_on_tree_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_tree_id ON public.wallets USING btree (tree_id);


--
-- Name: telemetry_logs_default_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_default_bio_status_created_at_idx ON public.telemetry_logs_default USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_default_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_default_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_default USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_default_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_default_tree_id_created_at_idx ON public.telemetry_logs_default USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_default_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_default_tree_id_idx ON public.telemetry_logs_default USING btree (tree_id);


--
-- Name: telemetry_logs_y2026m01_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m01_bio_status_created_at_idx ON public.telemetry_logs_y2026m01 USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_y2026m01_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m01_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_y2026m01 USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_y2026m01_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m01_tree_id_created_at_idx ON public.telemetry_logs_y2026m01 USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_y2026m01_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m01_tree_id_idx ON public.telemetry_logs_y2026m01 USING btree (tree_id);


--
-- Name: telemetry_logs_y2026m02_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m02_bio_status_created_at_idx ON public.telemetry_logs_y2026m02 USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_y2026m02_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m02_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_y2026m02 USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_y2026m02_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m02_tree_id_created_at_idx ON public.telemetry_logs_y2026m02 USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_y2026m02_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m02_tree_id_idx ON public.telemetry_logs_y2026m02 USING btree (tree_id);


--
-- Name: telemetry_logs_y2026m03_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m03_bio_status_created_at_idx ON public.telemetry_logs_y2026m03 USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_y2026m03_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m03_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_y2026m03 USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_y2026m03_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m03_tree_id_created_at_idx ON public.telemetry_logs_y2026m03 USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_y2026m03_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m03_tree_id_idx ON public.telemetry_logs_y2026m03 USING btree (tree_id);


--
-- Name: telemetry_logs_y2026m04_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m04_bio_status_created_at_idx ON public.telemetry_logs_y2026m04 USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_y2026m04_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m04_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_y2026m04 USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_y2026m04_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m04_tree_id_created_at_idx ON public.telemetry_logs_y2026m04 USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_y2026m04_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m04_tree_id_idx ON public.telemetry_logs_y2026m04 USING btree (tree_id);


--
-- Name: telemetry_logs_y2026m05_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m05_bio_status_created_at_idx ON public.telemetry_logs_y2026m05 USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_y2026m05_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m05_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_y2026m05 USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_y2026m05_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m05_tree_id_created_at_idx ON public.telemetry_logs_y2026m05 USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_y2026m05_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m05_tree_id_idx ON public.telemetry_logs_y2026m05 USING btree (tree_id);


--
-- Name: telemetry_logs_y2026m06_bio_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m06_bio_status_created_at_idx ON public.telemetry_logs_y2026m06 USING btree (bio_status, created_at);


--
-- Name: telemetry_logs_y2026m06_piezo_voltage_mv_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m06_piezo_voltage_mv_created_at_idx ON public.telemetry_logs_y2026m06 USING btree (piezo_voltage_mv, created_at);


--
-- Name: telemetry_logs_y2026m06_tree_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m06_tree_id_created_at_idx ON public.telemetry_logs_y2026m06 USING btree (tree_id, created_at);


--
-- Name: telemetry_logs_y2026m06_tree_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_logs_y2026m06_tree_id_idx ON public.telemetry_logs_y2026m06 USING btree (tree_id);


--
-- Name: gateway_telemetry_logs_default_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_default_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_default_pkey;


--
-- Name: gateway_telemetry_logs_default_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_default_queen_uid_created_at_idx;


--
-- Name: gateway_telemetry_logs_y2026m01_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_y2026m01_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_y2026m01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_y2026m01_pkey;


--
-- Name: gateway_telemetry_logs_y2026m01_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_y2026m01_queen_uid_created_at_idx;


--
-- Name: gateway_telemetry_logs_y2026m02_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_y2026m02_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_y2026m02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_y2026m02_pkey;


--
-- Name: gateway_telemetry_logs_y2026m02_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_y2026m02_queen_uid_created_at_idx;


--
-- Name: gateway_telemetry_logs_y2026m03_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_y2026m03_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_y2026m03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_y2026m03_pkey;


--
-- Name: gateway_telemetry_logs_y2026m03_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_y2026m03_queen_uid_created_at_idx;


--
-- Name: gateway_telemetry_logs_y2026m04_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_y2026m04_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_y2026m04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_y2026m04_pkey;


--
-- Name: gateway_telemetry_logs_y2026m04_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_y2026m04_queen_uid_created_at_idx;


--
-- Name: gateway_telemetry_logs_y2026m05_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_y2026m05_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_y2026m05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_y2026m05_pkey;


--
-- Name: gateway_telemetry_logs_y2026m05_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_y2026m05_queen_uid_created_at_idx;


--
-- Name: gateway_telemetry_logs_y2026m06_gateway_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_gateway_telemetry_logs_on_gateway_id ATTACH PARTITION public.gateway_telemetry_logs_y2026m06_gateway_id_idx;


--
-- Name: gateway_telemetry_logs_y2026m06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.gateway_telemetry_logs_pkey ATTACH PARTITION public.gateway_telemetry_logs_y2026m06_pkey;


--
-- Name: gateway_telemetry_logs_y2026m06_queen_uid_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_gateway_telemetry_logs_queen_uid_created ATTACH PARTITION public.gateway_telemetry_logs_y2026m06_queen_uid_created_at_idx;


--
-- Name: telemetry_logs_default_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_default_bio_status_created_at_idx;


--
-- Name: telemetry_logs_default_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_default_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_default_pkey;


--
-- Name: telemetry_logs_default_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_default_tree_id_created_at_idx;


--
-- Name: telemetry_logs_default_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_default_tree_id_idx;


--
-- Name: telemetry_logs_y2026m01_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_y2026m01_bio_status_created_at_idx;


--
-- Name: telemetry_logs_y2026m01_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_y2026m01_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_y2026m01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_y2026m01_pkey;


--
-- Name: telemetry_logs_y2026m01_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_y2026m01_tree_id_created_at_idx;


--
-- Name: telemetry_logs_y2026m01_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_y2026m01_tree_id_idx;


--
-- Name: telemetry_logs_y2026m02_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_y2026m02_bio_status_created_at_idx;


--
-- Name: telemetry_logs_y2026m02_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_y2026m02_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_y2026m02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_y2026m02_pkey;


--
-- Name: telemetry_logs_y2026m02_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_y2026m02_tree_id_created_at_idx;


--
-- Name: telemetry_logs_y2026m02_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_y2026m02_tree_id_idx;


--
-- Name: telemetry_logs_y2026m03_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_y2026m03_bio_status_created_at_idx;


--
-- Name: telemetry_logs_y2026m03_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_y2026m03_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_y2026m03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_y2026m03_pkey;


--
-- Name: telemetry_logs_y2026m03_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_y2026m03_tree_id_created_at_idx;


--
-- Name: telemetry_logs_y2026m03_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_y2026m03_tree_id_idx;


--
-- Name: telemetry_logs_y2026m04_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_y2026m04_bio_status_created_at_idx;


--
-- Name: telemetry_logs_y2026m04_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_y2026m04_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_y2026m04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_y2026m04_pkey;


--
-- Name: telemetry_logs_y2026m04_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_y2026m04_tree_id_created_at_idx;


--
-- Name: telemetry_logs_y2026m04_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_y2026m04_tree_id_idx;


--
-- Name: telemetry_logs_y2026m05_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_y2026m05_bio_status_created_at_idx;


--
-- Name: telemetry_logs_y2026m05_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_y2026m05_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_y2026m05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_y2026m05_pkey;


--
-- Name: telemetry_logs_y2026m05_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_y2026m05_tree_id_created_at_idx;


--
-- Name: telemetry_logs_y2026m05_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_y2026m05_tree_id_idx;


--
-- Name: telemetry_logs_y2026m06_bio_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_bio_status_created ATTACH PARTITION public.telemetry_logs_y2026m06_bio_status_created_at_idx;


--
-- Name: telemetry_logs_y2026m06_piezo_voltage_mv_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_telemetry_logs_piezo_created ATTACH PARTITION public.telemetry_logs_y2026m06_piezo_voltage_mv_created_at_idx;


--
-- Name: telemetry_logs_y2026m06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_logs_pkey ATTACH PARTITION public.telemetry_logs_y2026m06_pkey;


--
-- Name: telemetry_logs_y2026m06_tree_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id_and_created_at ATTACH PARTITION public.telemetry_logs_y2026m06_tree_id_created_at_idx;


--
-- Name: telemetry_logs_y2026m06_tree_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_logs_on_tree_id ATTACH PARTITION public.telemetry_logs_y2026m06_tree_id_idx;


--
-- Name: clusters trigger_sync_cluster_geo_boundary; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_sync_cluster_geo_boundary BEFORE INSERT OR UPDATE OF geojson_polygon ON public.clusters FOR EACH ROW EXECUTE FUNCTION public.sync_cluster_geo_boundary();


--
-- Name: gateway_telemetry_logs fk_gateway_telemetry_logs_gateway_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.gateway_telemetry_logs
    ADD CONSTRAINT fk_gateway_telemetry_logs_gateway_id FOREIGN KEY (gateway_id) REFERENCES public.gateways(id);


--
-- Name: trees fk_rails_06cda60c51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees
    ADD CONSTRAINT fk_rails_06cda60c51 FOREIGN KEY (tiny_ml_model_id) REFERENCES public.tiny_ml_models(id);


--
-- Name: audit_logs fk_rails_13aa3bd6ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_13aa3bd6ad FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: wallets fk_rails_1c72cbc225; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_rails_1c72cbc225 FOREIGN KEY (tree_id) REFERENCES public.trees(id);


--
-- Name: ews_alerts fk_rails_1d5041378e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ews_alerts
    ADD CONSTRAINT fk_rails_1d5041378e FOREIGN KEY (tree_id) REFERENCES public.trees(id);


--
-- Name: audit_logs fk_rails_1f26bc34ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_1f26bc34ae FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: parametric_insurances fk_rails_263c5e6bbe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametric_insurances
    ADD CONSTRAINT fk_rails_263c5e6bbe FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: wallets fk_rails_28077d4aa2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_rails_28077d4aa2 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: ews_alerts fk_rails_31dc7505cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ews_alerts
    ADD CONSTRAINT fk_rails_31dc7505cb FOREIGN KEY (resolved_by) REFERENCES public.users(id);


--
-- Name: trees fk_rails_3349fced79; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees
    ADD CONSTRAINT fk_rails_3349fced79 FOREIGN KEY (tree_family_id) REFERENCES public.tree_families(id);


--
-- Name: clusters fk_rails_43af04cf6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clusters
    ADD CONSTRAINT fk_rails_43af04cf6d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: maintenance_records fk_rails_51fb28965b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_records
    ADD CONSTRAINT fk_rails_51fb28965b FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: identities fk_rails_5373344100; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities
    ADD CONSTRAINT fk_rails_5373344100 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: gateways fk_rails_637a591322; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gateways
    ADD CONSTRAINT fk_rails_637a591322 FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: actuator_commands fk_rails_6458121e3f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuator_commands
    ADD CONSTRAINT fk_rails_6458121e3f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: actuator_commands fk_rails_7d7b1ea1d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuator_commands
    ADD CONSTRAINT fk_rails_7d7b1ea1d2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: blockchain_transactions fk_rails_7f57af4001; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_transactions
    ADD CONSTRAINT fk_rails_7f57af4001 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: tiny_ml_models fk_rails_8ebc5faedf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiny_ml_models
    ADD CONSTRAINT fk_rails_8ebc5faedf FOREIGN KEY (tree_family_id) REFERENCES public.tree_families(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: naas_contracts fk_rails_a66158730a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.naas_contracts
    ADD CONSTRAINT fk_rails_a66158730a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: bio_contract_firmwares fk_rails_c65d4e0323; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bio_contract_firmwares
    ADD CONSTRAINT fk_rails_c65d4e0323 FOREIGN KEY (tree_family_id) REFERENCES public.tree_families(id);


--
-- Name: trees fk_rails_c7140d4291; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees
    ADD CONSTRAINT fk_rails_c7140d4291 FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: naas_contracts fk_rails_cb132bb86f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.naas_contracts
    ADD CONSTRAINT fk_rails_cb132bb86f FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: blockchain_transactions fk_rails_d3cc5df71d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_transactions
    ADD CONSTRAINT fk_rails_d3cc5df71d FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: users fk_rails_d7b9ff90af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_d7b9ff90af FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: actuators fk_rails_db554b554e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuators
    ADD CONSTRAINT fk_rails_db554b554e FOREIGN KEY (gateway_id) REFERENCES public.gateways(id);


--
-- Name: maintenance_records fk_rails_e28c02059b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_records
    ADD CONSTRAINT fk_rails_e28c02059b FOREIGN KEY (ews_alert_id) REFERENCES public.ews_alerts(id);


--
-- Name: ews_alerts fk_rails_eef0559de4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ews_alerts
    ADD CONSTRAINT fk_rails_eef0559de4 FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: actuator_commands fk_rails_ef97c98747; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuator_commands
    ADD CONSTRAINT fk_rails_ef97c98747 FOREIGN KEY (actuator_id) REFERENCES public.actuators(id);


--
-- Name: parametric_insurances fk_rails_f74e36606e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametric_insurances
    ADD CONSTRAINT fk_rails_f74e36606e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: actuator_commands fk_rails_fb2abfc4a2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actuator_commands
    ADD CONSTRAINT fk_rails_fb2abfc4a2 FOREIGN KEY (ews_alert_id) REFERENCES public.ews_alerts(id);


--
-- Name: device_calibrations fk_rails_fc89db28c3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_calibrations
    ADD CONSTRAINT fk_rails_fc89db28c3 FOREIGN KEY (tree_id) REFERENCES public.trees(id);


--
-- Name: telemetry_logs fk_telemetry_logs_tree_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_logs
    ADD CONSTRAINT fk_telemetry_logs_tree_id FOREIGN KEY (tree_id) REFERENCES public.trees(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260310170000'),
('20260310160000'),
('20260309070000'),
('20260308160000'),
('20260308143801'),
('20260308143800'),
('20260308101003'),
('20260308101002'),
('20260308101001'),
('20260308101000'),
('20260308095001'),
('20260308095000'),
('20260308070000'),
('20260307093414'),
('20260226164445');

