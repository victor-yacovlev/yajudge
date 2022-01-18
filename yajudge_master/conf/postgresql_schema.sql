--
-- PostgreSQL database dump
--

-- Dumped from database version 14.1
-- Dumped by pg_dump version 14.1

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: courses; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.courses (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    course_data character varying(100) NOT NULL,
    url_prefix character varying(50) NOT NULL
);


ALTER TABLE public.courses OWNER TO test;

--
-- Name: courses_id_seq; Type: SEQUENCE; Schema: public; Owner: test
--

CREATE SEQUENCE public.courses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.courses_id_seq OWNER TO test;

--
-- Name: courses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: test
--

ALTER SEQUENCE public.courses_id_seq OWNED BY public.courses.id;


--
-- Name: enrollments; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.enrollments (
    id integer NOT NULL,
    courses_id integer NOT NULL,
    users_id integer NOT NULL,
    role integer NOT NULL
);


ALTER TABLE public.enrollments OWNER TO test;

--
-- Name: enrollments_id_seq; Type: SEQUENCE; Schema: public; Owner: test
--

CREATE SEQUENCE public.enrollments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.enrollments_id_seq OWNER TO test;

--
-- Name: enrollments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: test
--

ALTER SEQUENCE public.enrollments_id_seq OWNED BY public.enrollments.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.sessions (
    cookie character varying(64) NOT NULL,
    start timestamp without time zone NOT NULL,
    users_id integer NOT NULL
);


ALTER TABLE public.sessions OWNER TO test;

--
-- Name: submission_files; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.submission_files (
    id integer NOT NULL,
    file_name character varying(30) NOT NULL,
    content character varying NOT NULL,
    submissions_id integer NOT NULL
);


ALTER TABLE public.submission_files OWNER TO test;

--
-- Name: submission_files_id_seq; Type: SEQUENCE; Schema: public; Owner: test
--

CREATE SEQUENCE public.submission_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.submission_files_id_seq OWNER TO test;

--
-- Name: submission_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: test
--

ALTER SEQUENCE public.submission_files_id_seq OWNED BY public.submission_files.id;


--
-- Name: submission_results; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.submission_results (
    id integer NOT NULL,
    submissions_id integer NOT NULL,
    test_number integer NOT NULL,
    stdout character varying NOT NULL,
    stderr character varying NOT NULL,
    status integer NOT NULL,
    exited boolean NOT NULL,
    standard_match boolean NOT NULL
);


ALTER TABLE public.submission_results OWNER TO test;

--
-- Name: submission_results_id_seq; Type: SEQUENCE; Schema: public; Owner: test
--

CREATE SEQUENCE public.submission_results_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.submission_results_id_seq OWNER TO test;

--
-- Name: submission_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: test
--

ALTER SEQUENCE public.submission_results_id_seq OWNED BY public.submission_results.id;


--
-- Name: submissions; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.submissions (
    id integer NOT NULL,
    users_id integer NOT NULL,
    courses_id integer NOT NULL,
    problem_id character varying(100) NOT NULL,
    status integer NOT NULL,
    "timestamp" bigint NOT NULL,
    grader_name character varying(100),
    grader_output character varying,
    grader_errors character varying
);


ALTER TABLE public.submissions OWNER TO test;

--
-- Name: submissions_id_seq; Type: SEQUENCE; Schema: public; Owner: test
--

CREATE SEQUENCE public.submissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.submissions_id_seq OWNER TO test;

--
-- Name: submissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: test
--

ALTER SEQUENCE public.submissions_id_seq OWNED BY public.submissions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: test
--

CREATE TABLE public.users (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    mid_name character varying(50),
    email character varying(50),
    group_name character varying(30),
    default_role integer DEFAULT 0 NOT NULL,
    disabled boolean DEFAULT false NOT NULL
);


ALTER TABLE public.users OWNER TO test;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: test
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO test;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: test
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: courses id; Type: DEFAULT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.courses ALTER COLUMN id SET DEFAULT nextval('public.courses_id_seq'::regclass);


--
-- Name: enrollments id; Type: DEFAULT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.enrollments ALTER COLUMN id SET DEFAULT nextval('public.enrollments_id_seq'::regclass);


--
-- Name: submission_files id; Type: DEFAULT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submission_files ALTER COLUMN id SET DEFAULT nextval('public.submission_files_id_seq'::regclass);


--
-- Name: submission_results id; Type: DEFAULT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submission_results ALTER COLUMN id SET DEFAULT nextval('public.submission_results_id_seq'::regclass);


--
-- Name: submissions id; Type: DEFAULT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submissions ALTER COLUMN id SET DEFAULT nextval('public.submissions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: courses courses_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pk PRIMARY KEY (id);


--
-- Name: enrollments enrollments_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pk PRIMARY KEY (id);


--
-- Name: sessions sessions_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pk PRIMARY KEY (cookie);


--
-- Name: submission_files submission_files_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submission_files
    ADD CONSTRAINT submission_files_pk PRIMARY KEY (id);


--
-- Name: submission_results submission_results_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submission_results
    ADD CONSTRAINT submission_results_pk PRIMARY KEY (id);


--
-- Name: submissions submissions_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submissions
    ADD CONSTRAINT submissions_pk PRIMARY KEY (id);


--
-- Name: users users_pk; Type: CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pk PRIMARY KEY (id);


--
-- Name: enrollments enrollments_courses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_courses_id_fk FOREIGN KEY (courses_id) REFERENCES public.courses(id);


--
-- Name: enrollments enrollments_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_users_id_fk FOREIGN KEY (users_id) REFERENCES public.users(id);


--
-- Name: sessions sessions_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_users_id_fk FOREIGN KEY (users_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: submission_files submission_files_submissions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submission_files
    ADD CONSTRAINT submission_files_submissions_id_fk FOREIGN KEY (submissions_id) REFERENCES public.submissions(id);


--
-- Name: submissions submissions_courses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submissions
    ADD CONSTRAINT submissions_courses_id_fk FOREIGN KEY (courses_id) REFERENCES public.courses(id);


--
-- Name: submissions submissions_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: test
--

ALTER TABLE ONLY public.submissions
    ADD CONSTRAINT submissions_users_id_fk FOREIGN KEY (users_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

