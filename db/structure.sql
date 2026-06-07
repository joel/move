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
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    name character varying NOT NULL,
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
    category_id uuid
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
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: move_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.move_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'member'::character varying NOT NULL,
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
    auto_confirm_threshold numeric(3,2) DEFAULT 0.8 NOT NULL
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
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying,
    body text,
    user_id uuid NOT NULL,
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
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    move_id uuid NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    updated_at timestamp(6) without time zone NOT NULL
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
-- Name: media media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_pkey PRIMARY KEY (id);


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
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


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
-- Name: index_categories_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_on_move_id ON public.categories USING btree (move_id);


--
-- Name: index_categories_on_move_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_categories_on_move_id_and_name ON public.categories USING btree (move_id, name);


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
-- Name: index_media_on_box_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_media_on_box_id ON public.media USING btree (box_id);


--
-- Name: index_media_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_media_on_move_id ON public.media USING btree (move_id);


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
-- Name: index_posts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posts_on_user_id ON public.posts USING btree (user_id);


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
-- Name: index_recognition_suggestions_on_recognition_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recognition_suggestions_on_recognition_run_id ON public.recognition_suggestions USING btree (recognition_run_id);


--
-- Name: index_rooms_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rooms_on_move_id ON public.rooms USING btree (move_id);


--
-- Name: index_rooms_on_move_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rooms_on_move_id_and_name ON public.rooms USING btree (move_id, name);


--
-- Name: index_tags_on_move_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_move_id ON public.tags USING btree (move_id);


--
-- Name: index_tags_on_move_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tags_on_move_id_and_name ON public.tags USING btree (move_id, name);


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
-- Name: posts fk_rails_5b5ddfd518; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT fk_rails_5b5ddfd518 FOREIGN KEY (user_id) REFERENCES public.users(id);


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

