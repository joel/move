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
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
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
    updated_at timestamp(6) without time zone NOT NULL
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
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
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
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


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
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


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
-- Name: user_email_auth_keys fk_rails_1a2acb61d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_email_auth_keys
    ADD CONSTRAINT fk_rails_1a2acb61d1 FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: user_omniauth_identities fk_rails_8643d06e22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_omniauth_identities
    ADD CONSTRAINT fk_rails_8643d06e22 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: user_remember_keys fk_rails_ee6b3c037b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_remember_keys
    ADD CONSTRAINT fk_rails_ee6b3c037b FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "public";

INSERT INTO "schema_migrations" (version) VALUES
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

