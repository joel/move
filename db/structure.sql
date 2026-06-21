SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: logidze_capture_exception(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_capture_exception(error_data jsonb) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
  -- version: 1
BEGIN
  -- Feel free to change this function to change Logidze behavior on exception.
  --
  -- Return `false` to raise exception or `true` to commit record changes.
  --
  -- `error_data` contains:
  --   - returned_sqlstate
  --   - message_text
  --   - pg_exception_detail
  --   - pg_exception_hint
  --   - pg_exception_context
  --   - schema_name
  --   - table_name
  -- Learn more about available keys:
  -- https://www.postgresql.org/docs/9.6/plpgsql-control-structures.html#PLPGSQL-EXCEPTION-DIAGNOSTICS-VALUES
  --

  return false;
END;
$$;


--
-- Name: logidze_compact_history(jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_compact_history(log_data jsonb, cutoff integer DEFAULT 1) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 1
  DECLARE
    merged jsonb;
  BEGIN
    LOOP
      merged := jsonb_build_object(
        'ts',
        log_data#>'{h,1,ts}',
        'v',
        log_data#>'{h,1,v}',
        'c',
        (log_data#>'{h,0,c}') || (log_data#>'{h,1,c}')
      );

      IF (log_data#>'{h,1}' ? 'm') THEN
        merged := jsonb_set(merged, ARRAY['m'], log_data#>'{h,1,m}');
      END IF;

      log_data := jsonb_set(
        log_data,
        '{h}',
        jsonb_set(
          log_data->'h',
          '{1}',
          merged
        ) - 0
      );

      cutoff := cutoff - 1;

      EXIT WHEN cutoff <= 0;
    END LOOP;

    return log_data;
  END;
$$;


--
-- Name: logidze_filter_keys(jsonb, text[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_filter_keys(obj jsonb, keys text[], include_columns boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 1
  DECLARE
    res jsonb;
    key text;
  BEGIN
    res := '{}';

    IF include_columns THEN
      FOREACH key IN ARRAY keys
      LOOP
        IF obj ? key THEN
          res = jsonb_insert(res, ARRAY[key], obj->key);
        END IF;
      END LOOP;
    ELSE
      res = obj;
      FOREACH key IN ARRAY keys
      LOOP
        res = res - key;
      END LOOP;
    END IF;

    RETURN res;
  END;
$$;


--
-- Name: logidze_logger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_logger() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
  -- version: 5
  DECLARE
    changes jsonb;
    version jsonb;
    full_snapshot boolean;
    log_data jsonb;
    new_v integer;
    size integer;
    history_limit integer;
    debounce_time integer;
    current_version integer;
    k text;
    iterator integer;
    item record;
    columns text[];
    include_columns boolean;
    detached_log_data jsonb;
    -- We use `detached_loggable_type` for:
    -- 1. Checking if current implementation is `--detached` (`log_data` is stored in a separated table)
    -- 2. If implementation is `--detached` then we use detached_loggable_type to determine
    --    to which table current `log_data` record belongs
    detached_loggable_type text;
    log_data_table_name text;
    log_data_is_empty boolean;
    log_data_ts_key_data text;
    ts timestamp with time zone;
    ts_column text;
    err_sqlstate text;
    err_message text;
    err_detail text;
    err_hint text;
    err_context text;
    err_table_name text;
    err_schema_name text;
    err_jsonb jsonb;
    err_captured boolean;
  BEGIN
    ts_column := NULLIF(TG_ARGV[1], 'null');
    columns := NULLIF(TG_ARGV[2], 'null');
    include_columns := NULLIF(TG_ARGV[3], 'null');
    detached_loggable_type := NULLIF(TG_ARGV[5], 'null');
    log_data_table_name := NULLIF(TG_ARGV[6], 'null');

    -- getting previous log_data if it exists for detached `log_data` storage variant
    IF detached_loggable_type IS NOT NULL
    THEN
      EXECUTE format(
        'SELECT ldtn.log_data ' ||
        'FROM %I ldtn ' ||
        'WHERE ldtn.loggable_type = $1 ' ||
          'AND ldtn.loggable_id = $2 '  ||
        'LIMIT 1',
        log_data_table_name
      ) USING detached_loggable_type, NEW.id INTO detached_log_data;
    END IF;

    IF detached_loggable_type IS NULL
    THEN
        log_data_is_empty = NEW.log_data is NULL OR NEW.log_data = '{}'::jsonb;
    ELSE
        log_data_is_empty = detached_log_data IS NULL OR detached_log_data = '{}'::jsonb;
    END IF;

    IF log_data_is_empty
    THEN
      IF columns IS NOT NULL THEN
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column, columns, include_columns);
      ELSE
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column);
      END IF;

      IF log_data#>>'{h, -1, c}' != '{}' THEN
        IF detached_loggable_type IS NULL
        THEN
          NEW.log_data := log_data;
        ELSE
          EXECUTE format(
            'INSERT INTO %I(log_data, loggable_type, loggable_id) ' ||
            'VALUES ($1, $2, $3);',
            log_data_table_name
          ) USING log_data, detached_loggable_type, NEW.id;
        END IF;
      END IF;

    ELSE

      IF TG_OP = 'UPDATE' AND (to_jsonb(NEW.*) = to_jsonb(OLD.*)) THEN
        RETURN NEW; -- pass
      END IF;

      history_limit := NULLIF(TG_ARGV[0], 'null');
      debounce_time := NULLIF(TG_ARGV[4], 'null');

      IF detached_loggable_type IS NULL
      THEN
          log_data := NEW.log_data;
      ELSE
          log_data := detached_log_data;
      END IF;

      current_version := (log_data->>'v')::int;

      IF ts_column IS NULL THEN
        ts := statement_timestamp();
      ELSEIF TG_OP = 'UPDATE' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;
        IF ts IS NULL OR ts = (to_jsonb(OLD.*) ->> ts_column)::timestamp with time zone THEN
          ts := statement_timestamp();
        END IF;
      ELSEIF TG_OP = 'INSERT' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;

        IF detached_loggable_type IS NULL
        THEN
          log_data_ts_key_data = NEW.log_data #>> '{h,-1,ts}';
        ELSE
          log_data_ts_key_data = detached_log_data #>> '{h,-1,ts}';
        END IF;

        IF ts IS NULL OR (extract(epoch from ts) * 1000)::bigint = log_data_ts_key_data::bigint THEN
            ts := statement_timestamp();
        END IF;
      END IF;

      full_snapshot := (coalesce(current_setting('logidze.full_snapshot', true), '') = 'on') OR (TG_OP = 'INSERT');

      IF current_version < (log_data#>>'{h,-1,v}')::int THEN
        iterator := 0;
        FOR item in SELECT * FROM jsonb_array_elements(log_data->'h')
        LOOP
          IF (item.value->>'v')::int > current_version THEN
            log_data := jsonb_set(
              log_data,
              '{h}',
              (log_data->'h') - iterator
            );
          END IF;
          iterator := iterator + 1;
        END LOOP;
      END IF;

      changes := '{}';

      IF full_snapshot THEN
        BEGIN
          changes = hstore_to_jsonb_loose(hstore(NEW.*));
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = row_to_json(NEW.*)::jsonb;
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      ELSE
        BEGIN
          changes = hstore_to_jsonb_loose(
                hstore(NEW.*) - hstore(OLD.*)
            );
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = (SELECT
              COALESCE(json_object_agg(key, value), '{}')::jsonb
              FROM
              jsonb_each(row_to_json(NEW.*)::jsonb)
              WHERE NOT jsonb_build_object(key, value) <@ row_to_json(OLD.*)::jsonb);
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      END IF;

      -- We store `log_data` in a separate table for the `detached` mode
      -- So we remove `log_data` only when we store historic data in the record's origin table
      IF detached_loggable_type IS NULL
      THEN
          changes = changes - 'log_data';
      END IF;

      IF columns IS NOT NULL THEN
        changes = logidze_filter_keys(changes, columns, include_columns);
      END IF;

      IF changes = '{}' THEN
        RETURN NEW; -- pass
      END IF;

      new_v := (log_data#>>'{h,-1,v}')::int + 1;

      size := jsonb_array_length(log_data->'h');
      version := logidze_version(new_v, changes, ts);

      IF (
        debounce_time IS NOT NULL AND
        (version->>'ts')::bigint - (log_data#>'{h,-1,ts}')::text::bigint <= debounce_time
      ) THEN
        -- merge new version with the previous one
        new_v := (log_data#>>'{h,-1,v}')::int;
        version := logidze_version(new_v, (log_data#>'{h,-1,c}')::jsonb || changes, ts);
        -- remove the previous version from log
        log_data := jsonb_set(
          log_data,
          '{h}',
          (log_data->'h') - (size - 1)
        );
      END IF;

      log_data := jsonb_set(
        log_data,
        ARRAY['h', size::text],
        version,
        true
      );

      log_data := jsonb_set(
        log_data,
        '{v}',
        to_jsonb(new_v)
      );

      IF history_limit IS NOT NULL AND history_limit <= size THEN
        log_data := logidze_compact_history(log_data, size - history_limit + 1);
      END IF;

      IF detached_loggable_type IS NULL
      THEN
        NEW.log_data := log_data;
      ELSE
        detached_log_data = log_data;
        EXECUTE format(
          'UPDATE %I ' ||
          'SET log_data = $1 ' ||
          'WHERE %I.loggable_type = $2 ' ||
          'AND %I.loggable_id = $3',
          log_data_table_name,
          log_data_table_name,
          log_data_table_name
        ) USING detached_log_data, detached_loggable_type, NEW.id;
      END IF;
    END IF;

    RETURN NEW; -- result
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS err_sqlstate = RETURNED_SQLSTATE,
                              err_message = MESSAGE_TEXT,
                              err_detail = PG_EXCEPTION_DETAIL,
                              err_hint = PG_EXCEPTION_HINT,
                              err_context = PG_EXCEPTION_CONTEXT,
                              err_schema_name = SCHEMA_NAME,
                              err_table_name = TABLE_NAME;
      err_jsonb := jsonb_build_object(
        'returned_sqlstate', err_sqlstate,
        'message_text', err_message,
        'pg_exception_detail', err_detail,
        'pg_exception_hint', err_hint,
        'pg_exception_context', err_context,
        'schema_name', err_schema_name,
        'table_name', err_table_name
      );
      err_captured = logidze_capture_exception(err_jsonb);
      IF err_captured THEN
        return NEW;
      ELSE
        RAISE;
      END IF;
  END;
$_$;


--
-- Name: logidze_logger_after(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_logger_after() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
  -- version: 5


  DECLARE
    changes jsonb;
    version jsonb;
    full_snapshot boolean;
    log_data jsonb;
    new_v integer;
    size integer;
    history_limit integer;
    debounce_time integer;
    current_version integer;
    k text;
    iterator integer;
    item record;
    columns text[];
    include_columns boolean;
    detached_log_data jsonb;
    -- We use `detached_loggable_type` for:
    -- 1. Checking if current implementation is `--detached` (`log_data` is stored in a separated table)
    -- 2. If implementation is `--detached` then we use detached_loggable_type to determine
    --    to which table current `log_data` record belongs
    detached_loggable_type text;
    log_data_table_name text;
    log_data_is_empty boolean;
    log_data_ts_key_data text;
    ts timestamp with time zone;
    ts_column text;
    err_sqlstate text;
    err_message text;
    err_detail text;
    err_hint text;
    err_context text;
    err_table_name text;
    err_schema_name text;
    err_jsonb jsonb;
    err_captured boolean;
  BEGIN
    ts_column := NULLIF(TG_ARGV[1], 'null');
    columns := NULLIF(TG_ARGV[2], 'null');
    include_columns := NULLIF(TG_ARGV[3], 'null');
    detached_loggable_type := NULLIF(TG_ARGV[5], 'null');
    log_data_table_name := NULLIF(TG_ARGV[6], 'null');

    -- getting previous log_data if it exists for detached `log_data` storage variant
    IF detached_loggable_type IS NOT NULL
    THEN
      EXECUTE format(
        'SELECT ldtn.log_data ' ||
        'FROM %I ldtn ' ||
        'WHERE ldtn.loggable_type = $1 ' ||
          'AND ldtn.loggable_id = $2 '  ||
        'LIMIT 1',
        log_data_table_name
      ) USING detached_loggable_type, NEW.id INTO detached_log_data;
    END IF;

    IF detached_loggable_type IS NULL
    THEN
        log_data_is_empty = NEW.log_data is NULL OR NEW.log_data = '{}'::jsonb;
    ELSE
        log_data_is_empty = detached_log_data IS NULL OR detached_log_data = '{}'::jsonb;
    END IF;

    IF log_data_is_empty
    THEN
      IF columns IS NOT NULL THEN
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column, columns, include_columns);
      ELSE
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column);
      END IF;

      IF log_data#>>'{h, -1, c}' != '{}' THEN
        IF detached_loggable_type IS NULL
        THEN
          NEW.log_data := log_data;
        ELSE
          EXECUTE format(
            'INSERT INTO %I(log_data, loggable_type, loggable_id) ' ||
            'VALUES ($1, $2, $3);',
            log_data_table_name
          ) USING log_data, detached_loggable_type, NEW.id;
        END IF;
      END IF;

    ELSE

      IF TG_OP = 'UPDATE' AND (to_jsonb(NEW.*) = to_jsonb(OLD.*)) THEN
        RETURN NULL;
      END IF;

      history_limit := NULLIF(TG_ARGV[0], 'null');
      debounce_time := NULLIF(TG_ARGV[4], 'null');

      IF detached_loggable_type IS NULL
      THEN
          log_data := NEW.log_data;
      ELSE
          log_data := detached_log_data;
      END IF;

      current_version := (log_data->>'v')::int;

      IF ts_column IS NULL THEN
        ts := statement_timestamp();
      ELSEIF TG_OP = 'UPDATE' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;
        IF ts IS NULL OR ts = (to_jsonb(OLD.*) ->> ts_column)::timestamp with time zone THEN
          ts := statement_timestamp();
        END IF;
      ELSEIF TG_OP = 'INSERT' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;

        IF detached_loggable_type IS NULL
        THEN
          log_data_ts_key_data = NEW.log_data #>> '{h,-1,ts}';
        ELSE
          log_data_ts_key_data = detached_log_data #>> '{h,-1,ts}';
        END IF;

        IF ts IS NULL OR (extract(epoch from ts) * 1000)::bigint = log_data_ts_key_data::bigint THEN
            ts := statement_timestamp();
        END IF;
      END IF;

      full_snapshot := (coalesce(current_setting('logidze.full_snapshot', true), '') = 'on') OR (TG_OP = 'INSERT');

      IF current_version < (log_data#>>'{h,-1,v}')::int THEN
        iterator := 0;
        FOR item in SELECT * FROM jsonb_array_elements(log_data->'h')
        LOOP
          IF (item.value->>'v')::int > current_version THEN
            log_data := jsonb_set(
              log_data,
              '{h}',
              (log_data->'h') - iterator
            );
          END IF;
          iterator := iterator + 1;
        END LOOP;
      END IF;

      changes := '{}';

      IF full_snapshot THEN
        BEGIN
          changes = hstore_to_jsonb_loose(hstore(NEW.*));
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = row_to_json(NEW.*)::jsonb;
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      ELSE
        BEGIN
          changes = hstore_to_jsonb_loose(
                hstore(NEW.*) - hstore(OLD.*)
            );
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = (SELECT
              COALESCE(json_object_agg(key, value), '{}')::jsonb
              FROM
              jsonb_each(row_to_json(NEW.*)::jsonb)
              WHERE NOT jsonb_build_object(key, value) <@ row_to_json(OLD.*)::jsonb);
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      END IF;

      -- We store `log_data` in a separate table for the `detached` mode
      -- So we remove `log_data` only when we store historic data in the record's origin table
      IF detached_loggable_type IS NULL
      THEN
          changes = changes - 'log_data';
      END IF;

      IF columns IS NOT NULL THEN
        changes = logidze_filter_keys(changes, columns, include_columns);
      END IF;

      IF changes = '{}' THEN
        RETURN NULL;
      END IF;

      new_v := (log_data#>>'{h,-1,v}')::int + 1;

      size := jsonb_array_length(log_data->'h');
      version := logidze_version(new_v, changes, ts);

      IF (
        debounce_time IS NOT NULL AND
        (version->>'ts')::bigint - (log_data#>'{h,-1,ts}')::text::bigint <= debounce_time
      ) THEN
        -- merge new version with the previous one
        new_v := (log_data#>>'{h,-1,v}')::int;
        version := logidze_version(new_v, (log_data#>'{h,-1,c}')::jsonb || changes, ts);
        -- remove the previous version from log
        log_data := jsonb_set(
          log_data,
          '{h}',
          (log_data->'h') - (size - 1)
        );
      END IF;

      log_data := jsonb_set(
        log_data,
        ARRAY['h', size::text],
        version,
        true
      );

      log_data := jsonb_set(
        log_data,
        '{v}',
        to_jsonb(new_v)
      );

      IF history_limit IS NOT NULL AND history_limit <= size THEN
        log_data := logidze_compact_history(log_data, size - history_limit + 1);
      END IF;

      IF detached_loggable_type IS NULL
      THEN
        NEW.log_data := log_data;
      ELSE
        detached_log_data = log_data;
        EXECUTE format(
          'UPDATE %I ' ||
          'SET log_data = $1 ' ||
          'WHERE %I.loggable_type = $2 ' ||
          'AND %I.loggable_id = $3',
          log_data_table_name,
          log_data_table_name,
          log_data_table_name
        ) USING detached_log_data, detached_loggable_type, NEW.id;
      END IF;
    END IF;

    IF detached_loggable_type IS NULL
    THEN
      EXECUTE format('UPDATE %I.%I SET "log_data" = $1 WHERE ctid = %L', TG_TABLE_SCHEMA, TG_TABLE_NAME, NEW.CTID) USING NEW.log_data;
    END IF;

    RETURN NULL;

  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS err_sqlstate = RETURNED_SQLSTATE,
                              err_message = MESSAGE_TEXT,
                              err_detail = PG_EXCEPTION_DETAIL,
                              err_hint = PG_EXCEPTION_HINT,
                              err_context = PG_EXCEPTION_CONTEXT,
                              err_schema_name = SCHEMA_NAME,
                              err_table_name = TABLE_NAME;
      err_jsonb := jsonb_build_object(
        'returned_sqlstate', err_sqlstate,
        'message_text', err_message,
        'pg_exception_detail', err_detail,
        'pg_exception_hint', err_hint,
        'pg_exception_context', err_context,
        'schema_name', err_schema_name,
        'table_name', err_table_name
      );
      err_captured = logidze_capture_exception(err_jsonb);
      IF err_captured THEN
        return NEW;
      ELSE
        RAISE;
      END IF;
  END;
$_$;


--
-- Name: logidze_snapshot(jsonb, text, text[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_snapshot(item jsonb, ts_column text DEFAULT NULL::text, columns text[] DEFAULT NULL::text[], include_columns boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 3
  DECLARE
    ts timestamp with time zone;
    k text;
  BEGIN
    item = item - 'log_data';
    IF ts_column IS NULL THEN
      ts := statement_timestamp();
    ELSE
      ts := coalesce((item->>ts_column)::timestamp with time zone, statement_timestamp());
    END IF;

    IF columns IS NOT NULL THEN
      item := logidze_filter_keys(item, columns, include_columns);
    END IF;

    FOR k IN (SELECT key FROM jsonb_each(item))
    LOOP
      IF jsonb_typeof(item->k) = 'object' THEN
         item := jsonb_set(item, ARRAY[k], to_jsonb(item->>k));
      END IF;
    END LOOP;

    return json_build_object(
      'v', 1,
      'h', jsonb_build_array(
              logidze_version(1, item, ts)
            )
      );
  END;
$$;


--
-- Name: logidze_version(bigint, jsonb, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_version(v bigint, data jsonb, ts timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 2
  DECLARE
    buf jsonb;
  BEGIN
    data = data - 'log_data';
    buf := jsonb_build_object(
              'ts',
              (extract(epoch from ts) * 1000)::bigint,
              'v',
              v,
              'c',
              data
              );
    IF coalesce(current_setting('logidze.meta', true), '') <> '' THEN
      buf := jsonb_insert(buf, '{m}', current_setting('logidze.meta')::jsonb);
    END IF;
    RETURN buf;
  END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
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
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    actor_id uuid,
    action character varying NOT NULL,
    subject_type character varying,
    subject_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    source integer DEFAULT 0 NOT NULL,
    low_signal boolean DEFAULT false NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


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
-- Name: boxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.boxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    room_id uuid,
    number character varying NOT NULL,
    qr_token character varying NOT NULL,
    length_cm numeric(8,2),
    width_cm numeric(8,2),
    height_cm numeric(8,2),
    weight_kg numeric(8,2),
    status character varying DEFAULT 'packing'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    log_data jsonb,
    description text
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    log_data jsonb
);


--
-- Name: indexing_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indexing_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    provider character varying NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    completed_count integer DEFAULT 0 NOT NULL,
    failed_count integer DEFAULT 0 NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: item_search_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_search_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    move_id uuid NOT NULL,
    search_text text DEFAULT ''::text NOT NULL,
    search_tsvector tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, COALESCE(search_text, ''::text))) STORED,
    embedding public.vector(1536),
    embedding_model character varying,
    embedded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: item_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    box_id uuid NOT NULL,
    source_media_id uuid,
    source_recognition_suggestion_id uuid,
    name character varying,
    quantity integer DEFAULT 1 NOT NULL,
    fragile boolean DEFAULT false NOT NULL,
    confidence_score numeric(4,3),
    created_via character varying DEFAULT 'recognition'::character varying NOT NULL,
    review_state character varying DEFAULT 'pending_review'::character varying NOT NULL,
    presence_state character varying DEFAULT 'in_box'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    category_id uuid,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    log_data jsonb
);


--
-- Name: label_print_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.label_print_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    from_number bigint NOT NULL,
    to_number bigint NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    completed_count integer DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    box_id uuid NOT NULL,
    media_type character varying DEFAULT 'image'::character varying NOT NULL,
    captured_at timestamp(6) without time zone NOT NULL,
    captured_via character varying DEFAULT 'web'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    optimized_at timestamp(6) without time zone,
    original_byte_size bigint
);


--
-- Name: move_integration_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.move_integration_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    created_by_user_id uuid NOT NULL,
    name character varying NOT NULL,
    token_digest character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    last_used_at timestamp(6) without time zone,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: move_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.move_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'viewer'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: moves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.moves (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    status character varying DEFAULT 'planned'::character varying NOT NULL,
    planned_on date,
    origin_address character varying,
    destination_address character varying,
    unit_system character varying DEFAULT 'metric'::character varying NOT NULL,
    created_by_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    auto_confirm_threshold numeric(3,2) DEFAULT 0.8 NOT NULL,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    log_data jsonb,
    recognition_provider character varying DEFAULT 'fake'::character varying NOT NULL,
    openai_api_key text,
    anthropic_api_key text,
    gemini_api_key text,
    openai_model character varying,
    anthropic_model character varying,
    gemini_model character varying,
    embedding_provider character varying DEFAULT 'fake'::character varying NOT NULL,
    voyage_api_key text
);


--
-- Name: organization_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'member'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug public.citext NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recognition_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recognition_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    box_id uuid NOT NULL,
    media_id uuid NOT NULL,
    provider character varying NOT NULL,
    provider_model character varying,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    error_code character varying,
    error_message character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recognition_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recognition_suggestions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    box_id uuid NOT NULL,
    media_id uuid NOT NULL,
    recognition_run_id uuid NOT NULL,
    item_id uuid,
    proposed_name character varying NOT NULL,
    proposed_quantity integer DEFAULT 1 NOT NULL,
    proposed_fragile boolean,
    confidence_score numeric(4,3),
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    proposed_category_id uuid
);


--
-- Name: rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    log_data jsonb
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    applies_to character varying DEFAULT 'item'::character varying NOT NULL,
    discarded_at timestamp(6) without time zone,
    discard_batch_id uuid,
    discarded_by_parent_type character varying,
    discarded_by_parent_id uuid,
    log_data jsonb
);


--
-- Name: user_email_auth_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_email_auth_keys (
    id uuid NOT NULL,
    key character varying NOT NULL,
    deadline timestamp(6) without time zone NOT NULL,
    email_last_sent timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_omniauth_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_omniauth_identities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    provider character varying NOT NULL,
    uid character varying NOT NULL
);


--
-- Name: user_remember_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_remember_keys (
    id uuid NOT NULL,
    key character varying NOT NULL,
    deadline timestamp(6) without time zone NOT NULL
);


--
-- Name: user_verification_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_verification_keys (
    id uuid NOT NULL,
    key character varying NOT NULL,
    requested_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    email_last_sent timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_webauthn_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_webauthn_keys (
    user_id uuid NOT NULL,
    webauthn_id character varying NOT NULL,
    public_key character varying NOT NULL,
    sign_count integer NOT NULL,
    last_use timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    name character varying(80)
);


--
-- Name: user_webauthn_user_ids; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_webauthn_user_ids (
    id uuid NOT NULL,
    webauthn_id character varying NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    email public.citext NOT NULL,
    roles_mask integer DEFAULT 0 NOT NULL
);


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
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: boxes boxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boxes
    ADD CONSTRAINT boxes_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: indexing_runs indexing_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexing_runs
    ADD CONSTRAINT indexing_runs_pkey PRIMARY KEY (id);


--
-- Name: item_search_documents item_search_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_search_documents
    ADD CONSTRAINT item_search_documents_pkey PRIMARY KEY (id);


--
-- Name: item_tags item_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_tags
    ADD CONSTRAINT item_tags_pkey PRIMARY KEY (id);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- Name: label_print_runs label_print_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_print_runs
    ADD CONSTRAINT label_print_runs_pkey PRIMARY KEY (id);


--
-- Name: media media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_pkey PRIMARY KEY (id);


--
-- Name: move_integration_tokens move_integration_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.move_integration_tokens
    ADD CONSTRAINT move_integration_tokens_pkey PRIMARY KEY (id);


--
-- Name: move_memberships move_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.move_memberships
    ADD CONSTRAINT move_memberships_pkey PRIMARY KEY (id);


--
-- Name: moves moves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moves
    ADD CONSTRAINT moves_pkey PRIMARY KEY (id);


--
-- Name: organization_memberships organization_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: recognition_runs recognition_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_runs
    ADD CONSTRAINT recognition_runs_pkey PRIMARY KEY (id);


--
-- Name: recognition_suggestions recognition_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT recognition_suggestions_pkey PRIMARY KEY (id);


--
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: user_email_auth_keys user_email_auth_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_email_auth_keys
    ADD CONSTRAINT user_email_auth_keys_pkey PRIMARY KEY (id);


--
-- Name: user_omniauth_identities user_omniauth_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_omniauth_identities
    ADD CONSTRAINT user_omniauth_identities_pkey PRIMARY KEY (id);


--
-- Name: user_remember_keys user_remember_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_remember_keys
    ADD CONSTRAINT user_remember_keys_pkey PRIMARY KEY (id);


--
-- Name: user_verification_keys user_verification_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_verification_keys
    ADD CONSTRAINT user_verification_keys_pkey PRIMARY KEY (id);


--
-- Name: user_webauthn_keys user_webauthn_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_webauthn_keys
    ADD CONSTRAINT user_webauthn_keys_pkey PRIMARY KEY (user_id, webauthn_id);


--
-- Name: user_webauthn_user_ids user_webauthn_user_ids_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_webauthn_user_ids
    ADD CONSTRAINT user_webauthn_user_ids_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_omniauth_identities_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_omniauth_identities_uniqueness ON public.user_omniauth_identities USING btree (provider, uid);


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
-- Name: index_activities_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_move_id ON public.activities USING btree (move_id);


--
-- Name: index_activities_on_move_id_and_occurred_at_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_move_id_and_occurred_at_and_id ON public.activities USING btree (move_id, occurred_at DESC, id DESC);


--
-- Name: index_activities_on_subject_type_and_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_subject_type_and_subject_id ON public.activities USING btree (subject_type, subject_id);


--
-- Name: index_boxes_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boxes_on_discard_batch_id ON public.boxes USING btree (discard_batch_id);


--
-- Name: index_boxes_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boxes_on_discarded_at ON public.boxes USING btree (discarded_at);


--
-- Name: index_boxes_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boxes_on_move_id ON public.boxes USING btree (move_id);


--
-- Name: index_boxes_on_move_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_boxes_on_move_id_and_number ON public.boxes USING btree (move_id, number);


--
-- Name: index_boxes_on_qr_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_boxes_on_qr_token ON public.boxes USING btree (qr_token);


--
-- Name: index_boxes_on_room_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boxes_on_room_id ON public.boxes USING btree (room_id);


--
-- Name: index_boxes_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boxes_on_status ON public.boxes USING btree (status);


--
-- Name: index_categories_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_on_discard_batch_id ON public.categories USING btree (discard_batch_id);


--
-- Name: index_categories_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_on_discarded_at ON public.categories USING btree (discarded_at);


--
-- Name: index_categories_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_on_move_id ON public.categories USING btree (move_id);


--
-- Name: index_categories_on_move_id_and_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_categories_on_move_id_and_lower_name ON public.categories USING btree (move_id, lower((name)::text));


--
-- Name: index_indexing_runs_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_indexing_runs_on_move_id ON public.indexing_runs USING btree (move_id);


--
-- Name: index_indexing_runs_on_move_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_indexing_runs_on_move_id_and_status ON public.indexing_runs USING btree (move_id, status);


--
-- Name: index_item_search_documents_on_embedding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_item_search_documents_on_embedding ON public.item_search_documents USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: index_item_search_documents_on_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_item_search_documents_on_item_id ON public.item_search_documents USING btree (item_id);


--
-- Name: index_item_search_documents_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_item_search_documents_on_move_id ON public.item_search_documents USING btree (move_id);


--
-- Name: index_item_search_documents_on_search_text_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_item_search_documents_on_search_text_trgm ON public.item_search_documents USING gin (search_text public.gin_trgm_ops);


--
-- Name: index_item_search_documents_on_search_tsvector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_item_search_documents_on_search_tsvector ON public.item_search_documents USING gin (search_tsvector);


--
-- Name: index_item_tags_on_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_item_tags_on_item_id ON public.item_tags USING btree (item_id);


--
-- Name: index_item_tags_on_item_id_and_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_item_tags_on_item_id_and_tag_id ON public.item_tags USING btree (item_id, tag_id);


--
-- Name: index_item_tags_on_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_item_tags_on_tag_id ON public.item_tags USING btree (tag_id);


--
-- Name: index_items_on_box_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_box_id ON public.items USING btree (box_id);


--
-- Name: index_items_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_category_id ON public.items USING btree (category_id);


--
-- Name: index_items_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_discard_batch_id ON public.items USING btree (discard_batch_id);


--
-- Name: index_items_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_discarded_at ON public.items USING btree (discarded_at);


--
-- Name: index_items_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_move_id ON public.items USING btree (move_id);


--
-- Name: index_items_on_review_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_review_state ON public.items USING btree (review_state);


--
-- Name: index_items_on_source_media_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_items_on_source_media_id ON public.items USING btree (source_media_id);


--
-- Name: index_label_print_runs_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_print_runs_on_move_id ON public.label_print_runs USING btree (move_id);


--
-- Name: index_label_print_runs_on_move_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_print_runs_on_move_id_and_status ON public.label_print_runs USING btree (move_id, status);


--
-- Name: index_media_on_box_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_media_on_box_id ON public.media USING btree (box_id);


--
-- Name: index_media_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_media_on_discard_batch_id ON public.media USING btree (discard_batch_id);


--
-- Name: index_media_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_media_on_discarded_at ON public.media USING btree (discarded_at);


--
-- Name: index_media_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_media_on_move_id ON public.media USING btree (move_id);


--
-- Name: index_move_integration_tokens_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_move_integration_tokens_on_created_by_user_id ON public.move_integration_tokens USING btree (created_by_user_id);


--
-- Name: index_move_integration_tokens_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_move_integration_tokens_on_move_id ON public.move_integration_tokens USING btree (move_id);


--
-- Name: index_move_integration_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_move_integration_tokens_on_token_digest ON public.move_integration_tokens USING btree (token_digest);


--
-- Name: index_move_memberships_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_move_memberships_on_move_id ON public.move_memberships USING btree (move_id);


--
-- Name: index_move_memberships_on_move_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_move_memberships_on_move_id_and_user_id ON public.move_memberships USING btree (move_id, user_id);


--
-- Name: index_move_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_move_memberships_on_user_id ON public.move_memberships USING btree (user_id);


--
-- Name: index_moves_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moves_on_created_by_id ON public.moves USING btree (created_by_id);


--
-- Name: index_moves_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moves_on_discard_batch_id ON public.moves USING btree (discard_batch_id);


--
-- Name: index_moves_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moves_on_discarded_at ON public.moves USING btree (discarded_at);


--
-- Name: index_moves_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moves_on_status ON public.moves USING btree (status);


--
-- Name: index_organization_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_organization_id ON public.organization_memberships USING btree (organization_id);


--
-- Name: index_organization_memberships_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organization_memberships_on_organization_id_and_user_id ON public.organization_memberships USING btree (organization_id, user_id);


--
-- Name: index_organization_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_user_id ON public.organization_memberships USING btree (user_id);


--
-- Name: index_organizations_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_slug ON public.organizations USING btree (slug);


--
-- Name: index_recognition_runs_on_box_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_runs_on_box_id ON public.recognition_runs USING btree (box_id);


--
-- Name: index_recognition_runs_on_media_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_runs_on_media_id ON public.recognition_runs USING btree (media_id);


--
-- Name: index_recognition_runs_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_runs_on_move_id ON public.recognition_runs USING btree (move_id);


--
-- Name: index_recognition_runs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_runs_on_status ON public.recognition_runs USING btree (status);


--
-- Name: index_recognition_suggestions_on_box_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_box_id ON public.recognition_suggestions USING btree (box_id);


--
-- Name: index_recognition_suggestions_on_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_item_id ON public.recognition_suggestions USING btree (item_id);


--
-- Name: index_recognition_suggestions_on_media_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_media_id ON public.recognition_suggestions USING btree (media_id);


--
-- Name: index_recognition_suggestions_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_move_id ON public.recognition_suggestions USING btree (move_id);


--
-- Name: index_recognition_suggestions_on_proposed_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_proposed_category_id ON public.recognition_suggestions USING btree (proposed_category_id);


--
-- Name: index_recognition_suggestions_on_recognition_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_recognition_run_id ON public.recognition_suggestions USING btree (recognition_run_id);


--
-- Name: index_rooms_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rooms_on_discard_batch_id ON public.rooms USING btree (discard_batch_id);


--
-- Name: index_rooms_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rooms_on_discarded_at ON public.rooms USING btree (discarded_at);


--
-- Name: index_rooms_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rooms_on_move_id ON public.rooms USING btree (move_id);


--
-- Name: index_rooms_on_move_id_and_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rooms_on_move_id_and_lower_name ON public.rooms USING btree (move_id, lower((name)::text));


--
-- Name: index_tags_on_discard_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_discard_batch_id ON public.tags USING btree (discard_batch_id);


--
-- Name: index_tags_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_discarded_at ON public.tags USING btree (discarded_at);


--
-- Name: index_tags_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_move_id ON public.tags USING btree (move_id);


--
-- Name: index_tags_on_move_id_and_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tags_on_move_id_and_lower_name ON public.tags USING btree (move_id, lower((name)::text));


--
-- Name: index_user_omniauth_identities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_omniauth_identities_on_user_id ON public.user_omniauth_identities USING btree (user_id);


--
-- Name: index_user_webauthn_keys_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_webauthn_keys_on_user_id ON public.user_webauthn_keys USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email) WHERE (status = ANY (ARRAY[1, 2]));


--
-- Name: boxes logidze_on_boxes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logidze_on_boxes BEFORE INSERT OR UPDATE ON public.boxes FOR EACH ROW WHEN ((COALESCE(current_setting('logidze.disabled'::text, true), ''::text) <> 'on'::text)) EXECUTE FUNCTION public.logidze_logger('null', 'updated_at', '{number, room_id, length_cm, width_cm, height_cm, weight_kg, description}', 'true');


--
-- Name: categories logidze_on_categories; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logidze_on_categories BEFORE INSERT OR UPDATE ON public.categories FOR EACH ROW WHEN ((COALESCE(current_setting('logidze.disabled'::text, true), ''::text) <> 'on'::text)) EXECUTE FUNCTION public.logidze_logger('null', 'updated_at', '{name}', 'true');


--
-- Name: items logidze_on_items; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logidze_on_items BEFORE INSERT OR UPDATE ON public.items FOR EACH ROW WHEN ((COALESCE(current_setting('logidze.disabled'::text, true), ''::text) <> 'on'::text)) EXECUTE FUNCTION public.logidze_logger('null', 'updated_at', '{name, category_id, quantity, fragile}', 'true');


--
-- Name: moves logidze_on_moves; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logidze_on_moves BEFORE INSERT OR UPDATE ON public.moves FOR EACH ROW WHEN ((COALESCE(current_setting('logidze.disabled'::text, true), ''::text) <> 'on'::text)) EXECUTE FUNCTION public.logidze_logger('null', 'updated_at', '{name, unit_system, auto_confirm_threshold}', 'true');


--
-- Name: rooms logidze_on_rooms; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logidze_on_rooms BEFORE INSERT OR UPDATE ON public.rooms FOR EACH ROW WHEN ((COALESCE(current_setting('logidze.disabled'::text, true), ''::text) <> 'on'::text)) EXECUTE FUNCTION public.logidze_logger('null', 'updated_at', '{name}', 'true');


--
-- Name: tags logidze_on_tags; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logidze_on_tags BEFORE INSERT OR UPDATE ON public.tags FOR EACH ROW WHEN ((COALESCE(current_setting('logidze.disabled'::text, true), ''::text) <> 'on'::text)) EXECUTE FUNCTION public.logidze_logger('null', 'updated_at', '{name, applies_to}', 'true');


--
-- Name: categories fk_rails_01f841557e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT fk_rails_01f841557e FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: recognition_suggestions fk_rails_0883acd32d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT fk_rails_0883acd32d FOREIGN KEY (recognition_run_id) REFERENCES public.recognition_runs(id);


--
-- Name: recognition_suggestions fk_rails_0a1702672a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT fk_rails_0a1702672a FOREIGN KEY (box_id) REFERENCES public.boxes(id);


--
-- Name: recognition_runs fk_rails_12e3ae5fdd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_runs
    ADD CONSTRAINT fk_rails_12e3ae5fdd FOREIGN KEY (media_id) REFERENCES public.media(id);


--
-- Name: user_email_auth_keys fk_rails_1a2acb61d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_email_auth_keys
    ADD CONSTRAINT fk_rails_1a2acb61d1 FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: recognition_suggestions fk_rails_1a790bf4bd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT fk_rails_1a790bf4bd FOREIGN KEY (item_id) REFERENCES public.items(id);


--
-- Name: items fk_rails_26cde3138d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT fk_rails_26cde3138d FOREIGN KEY (box_id) REFERENCES public.boxes(id);


--
-- Name: item_tags fk_rails_2774a12fa0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_tags
    ADD CONSTRAINT fk_rails_2774a12fa0 FOREIGN KEY (item_id) REFERENCES public.items(id);


--
-- Name: move_integration_tokens fk_rails_2b00dd7f7c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.move_integration_tokens
    ADD CONSTRAINT fk_rails_2b00dd7f7c FOREIGN KEY (move_id) REFERENCES public.moves(id) ON DELETE CASCADE;


--
-- Name: recognition_suggestions fk_rails_320e554aa8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT fk_rails_320e554aa8 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: recognition_runs fk_rails_38114b708d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_runs
    ADD CONSTRAINT fk_rails_38114b708d FOREIGN KEY (box_id) REFERENCES public.boxes(id);


--
-- Name: items fk_rails_3bf62e79fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT fk_rails_3bf62e79fb FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: label_print_runs fk_rails_4324e4d4b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_print_runs
    ADD CONSTRAINT fk_rails_4324e4d4b8 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: activities fk_rails_4378dca565; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_4378dca565 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: media fk_rails_4e64a33103; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT fk_rails_4e64a33103 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: recognition_suggestions fk_rails_56e971506f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT fk_rails_56e971506f FOREIGN KEY (media_id) REFERENCES public.media(id);


--
-- Name: organization_memberships fk_rails_57cf70d280; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_57cf70d280 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: tags fk_rails_62c57c7a1f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT fk_rails_62c57c7a1f FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: media fk_rails_6dfa82d09b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT fk_rails_6dfa82d09b FOREIGN KEY (box_id) REFERENCES public.boxes(id);


--
-- Name: user_webauthn_user_ids fk_rails_70a7526cb9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_webauthn_user_ids
    ADD CONSTRAINT fk_rails_70a7526cb9 FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: organization_memberships fk_rails_715ab7f4fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_715ab7f4fe FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: rooms fk_rails_717ed49701; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT fk_rails_717ed49701 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: boxes fk_rails_809086bda1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boxes
    ADD CONSTRAINT fk_rails_809086bda1 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: user_omniauth_identities fk_rails_8643d06e22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_omniauth_identities
    ADD CONSTRAINT fk_rails_8643d06e22 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: items fk_rails_89fb86dc8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT fk_rails_89fb86dc8b FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: recognition_suggestions fk_rails_9156700172; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_suggestions
    ADD CONSTRAINT fk_rails_9156700172 FOREIGN KEY (proposed_category_id) REFERENCES public.categories(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: move_memberships fk_rails_a80e7a5ec3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.move_memberships
    ADD CONSTRAINT fk_rails_a80e7a5ec3 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: user_webauthn_keys fk_rails_a8aa560c7f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_webauthn_keys
    ADD CONSTRAINT fk_rails_a8aa560c7f FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: indexing_runs fk_rails_ad76a40776; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexing_runs
    ADD CONSTRAINT fk_rails_ad76a40776 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: item_search_documents fk_rails_b44f0ebef7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_search_documents
    ADD CONSTRAINT fk_rails_b44f0ebef7 FOREIGN KEY (move_id) REFERENCES public.moves(id) ON DELETE CASCADE;


--
-- Name: user_verification_keys fk_rails_b5d6b8f85b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_verification_keys
    ADD CONSTRAINT fk_rails_b5d6b8f85b FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: items fk_rails_c7c0e718a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT fk_rails_c7c0e718a0 FOREIGN KEY (source_media_id) REFERENCES public.media(id);


--
-- Name: recognition_runs fk_rails_c912f85210; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognition_runs
    ADD CONSTRAINT fk_rails_c912f85210 FOREIGN KEY (move_id) REFERENCES public.moves(id);


--
-- Name: boxes fk_rails_d7ba44d4a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boxes
    ADD CONSTRAINT fk_rails_d7ba44d4a0 FOREIGN KEY (room_id) REFERENCES public.rooms(id);


--
-- Name: item_search_documents fk_rails_e5a5152ee5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_search_documents
    ADD CONSTRAINT fk_rails_e5a5152ee5 FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: item_tags fk_rails_edc62a420c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_tags
    ADD CONSTRAINT fk_rails_edc62a420c FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: user_remember_keys fk_rails_ee6b3c037b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_remember_keys
    ADD CONSTRAINT fk_rails_ee6b3c037b FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "public";

INSERT INTO "schema_migrations" (version) VALUES
('20260621140000'),
('20260621120000'),
('20260619072859'),
('20260617130000'),
('20260617120000'),
('20260616170001'),
('20260616170000'),
('20260616160000'),
('20260616120000'),
('20260616090000'),
('20260615120000'),
('20260614180625'),
('20260614180624'),
('20260614180623'),
('20260614180622'),
('20260614180621'),
('20260614180620'),
('20260614180619'),
('20260614180618'),
('20260614180617'),
('20260614180616'),
('20260613120001'),
('20260609130001'),
('20260609120001'),
('20260608090002'),
('20260608090001'),
('20260607130001'),
('20260607120004'),
('20260607120003'),
('20260607120002'),
('20260607120001'),
('20260606170315'),
('20260606170314'),
('20260606170313'),
('20260606170312'),
('20260606170311'),
('20260606170310'),
('20260606120002'),
('20260606120001'),
('20260604200004'),
('20260604200003'),
('20260604200002'),
('20260604200001'),
('20260603160000'),
('20260118160000'),
('20260118150143'),
('20260118150142'),
('20260118150141'),
('20260118150119'),
('20260118150118'),
('20260118150117');

