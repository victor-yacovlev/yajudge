CREATE TABLE public.courses (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    course_data character varying(100) NOT NULL,
    url_prefix character varying(50) NOT NULL,
    no_teacher_mode boolean DEFAULT true NOT NULL,
    must_solve_all_required_problems_to_complete boolean DEFAULT false
);


CREATE SEQUENCE public.courses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.courses_id_seq OWNED BY public.courses.id;


CREATE TABLE public.personal_enrollments (
    id integer NOT NULL,
    courses_id integer NOT NULL,
    users_id integer NOT NULL,
    role integer NOT NULL,
    group_pattern varchar(30) NOT NULL DEFAULT ''
);


CREATE SEQUENCE public.personal_enrollments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.personal_enrollments_id_seq OWNED BY public.personal_enrollments.id;


CREATE TABLE public.group_enrollments (
    id integer NOT NULL,
    courses_id integer NOT NULL,
    group_pattern varchar(30) NOT NULL
);


CREATE SEQUENCE public.group_enrollments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.group_enrollments_id_seq OWNED BY public.group_enrollments.id;


CREATE TABLE public.sessions (
    cookie character varying(64) NOT NULL,
    start timestamp without time zone NOT NULL,
    users_id integer NOT NULL
);


CREATE TABLE public.submission_files (
    id integer NOT NULL,
    file_name character varying(80) NOT NULL,
    content character varying NOT NULL,
    submissions_id integer NOT NULL
);

CREATE SEQUENCE public.submission_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.submission_files_id_seq OWNED BY public.submission_files.id;


CREATE TABLE public.submission_results (
    id integer NOT NULL,
    submissions_id integer NOT NULL,
    test_number integer NOT NULL,
    stdout character varying NOT NULL,
    stderr character varying NOT NULL,
    status integer NOT NULL,
    standard_match boolean NOT NULL,
    signal_killed integer NOT NULL,
    valgrind_errors integer NOT NULL,
    valgrind_output character varying NOT NULL,
    killed_by_timer boolean NOT NULL,
    checker_output character varying DEFAULT ''::character varying NOT NULL,
    exit_status integer DEFAULT 0 NOT NULL
);


CREATE SEQUENCE public.submission_results_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.submission_results_id_seq OWNED BY public.submission_results.id;


CREATE TABLE public.submissions (
    id integer NOT NULL,
    users_id integer NOT NULL,
    courses_id integer NOT NULL,
    problem_id character varying(100) NOT NULL,
    status integer NOT NULL,
    "timestamp" bigint NOT NULL,
    grader_name character varying(100),
    style_error_log character varying,
    compile_error_log character varying
);

CREATE SEQUENCE public.submissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.submissions_id_seq OWNED BY public.submissions.id;


CREATE TABLE public.users (
    id integer NOT NULL,
    login character varying(30),
    password character varying(128) NOT NULL,
    first_name character varying(50),
    last_name character varying(50),
    mid_name character varying(50),
    email character varying(50),
    group_name character varying(30),
    default_role integer DEFAULT 0 NOT NULL,
    disabled boolean DEFAULT false NOT NULL
);


CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;



ALTER TABLE ONLY public.courses ALTER COLUMN id SET DEFAULT nextval('public.courses_id_seq'::regclass);
ALTER TABLE ONLY public.enrollments ALTER COLUMN id SET DEFAULT nextval('public.enrollments_id_seq'::regclass);
ALTER TABLE ONLY public.submission_files ALTER COLUMN id SET DEFAULT nextval('public.submission_files_id_seq'::regclass);
ALTER TABLE ONLY public.submission_results ALTER COLUMN id SET DEFAULT nextval('public.submission_results_id_seq'::regclass);
ALTER TABLE ONLY public.submissions ALTER COLUMN id SET DEFAULT nextval('public.submissions_id_seq'::regclass);
ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pk PRIMARY KEY (id);

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pk PRIMARY KEY (id);

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pk PRIMARY KEY (cookie);

ALTER TABLE ONLY public.submission_files
    ADD CONSTRAINT submission_files_pk PRIMARY KEY (id);

ALTER TABLE ONLY public.submission_results
    ADD CONSTRAINT submission_results_pk PRIMARY KEY (id);

ALTER TABLE ONLY public.submissions
    ADD CONSTRAINT submissions_pk PRIMARY KEY (id);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pk PRIMARY KEY (id);


CREATE INDEX submission_results_target_index ON public.submission_results USING btree (submissions_id);


ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_users_id_fk FOREIGN KEY (users_id) REFERENCES public.users(id) ON DELETE CASCADE;


ALTER TABLE ONLY public.submission_files
    ADD CONSTRAINT submission_files_submissions_id_fk FOREIGN KEY (submissions_id) REFERENCES public.submissions(id);

ALTER TABLE ONLY public.submissions
    ADD CONSTRAINT submissions_courses_id_fk FOREIGN KEY (courses_id) REFERENCES public.courses(id);

ALTER TABLE ONLY public.submissions
    ADD CONSTRAINT submissions_users_id_fk FOREIGN KEY (users_id) REFERENCES public.users(id);
