create table if not exists courses
(
    id                                           serial
        constraint courses_pk
            primary key,
    name                                         varchar(50)  not null,
    course_data                                  varchar(100) not null,
    url_prefix                                   varchar(50)  not null,
    must_solve_all_required_problems_to_complete boolean default false,
    disable_review                               boolean default false,
    disable_defence                              boolean default true
);


create table if not exists submission_results
(
    id              serial
        constraint submission_results_pk
            primary key,
    submissions_id  integer                               not null,
    test_number     integer                               not null,
    stdout          varchar                               not null,
    stderr          varchar                               not null,
    status          integer                               not null,
    standard_match  boolean                               not null,
    signal_killed   integer                               not null,
    valgrind_errors integer                               not null,
    valgrind_output varchar                               not null,
    killed_by_timer boolean                               not null,
    checker_output  varchar default ''::character varying not null,
    exit_status     integer default 0                     not null
);


create index if not exists submission_results_target_index
    on submission_results (submissions_id);

create table if not exists users
(
    id           serial
        constraint users_pk
            primary key,
    password     varchar(128)          not null,
    first_name   varchar(50),
    last_name    varchar(50),
    mid_name     varchar(50),
    email        varchar(50),
    group_name   varchar(30),
    default_role integer default 0     not null,
    disabled     boolean default false not null,
    login        varchar(30)
);


create table if not exists personal_enrollments
(
    id            integer     default nextval('enrollments_id_seq'::regclass) not null
        constraint enrollments_pk
            primary key,
    courses_id    integer                                                     not null
        constraint enrollments_courses_id_fk
            references courses,
    users_id      integer                                                     not null
        constraint enrollments_users_id_fk
            references users,
    role          integer                                                     not null,
    group_pattern varchar(30) default ''::character varying                   not null
);


create table if not exists sessions
(
    cookie   varchar(64) not null
        constraint sessions_pk
            primary key,
    start    timestamp   not null,
    users_id integer     not null
        constraint sessions_users_id_fk
            references users
            on delete cascade
);


create table submissions
(
    id                serial
        constraint submissions_pk
            primary key,
    users_id          integer           not null
        constraint submissions_users_id_fk
            references users,
    courses_id        integer           not null
        constraint submissions_courses_id_fk
            references courses,
    problem_id        varchar(100)      not null,
    status            integer           not null,
    timestamp         bigint            not null,
    grader_name       varchar(100),
    style_error_log   varchar,
    compile_error_log varchar,
    grading_status    integer default 0 not null
);


create table if not exists submission_files
(
    id             integer default nextval('submission_files_id_seq'::regclass) not null
        constraint submission_files_pk
            primary key,
    file_name      varchar(30)                                                  not null,
    content        varchar                                                      not null,
    submissions_id integer                                                      not null
        constraint submission_files_submissions_id_fk
            references submissions
);


create unique index if not exists users_login_uindex
    on users (login);

create table if not exists group_enrollments
(
    id            serial
        constraint group_enrollments_pk
            primary key,
    courses_id    integer     not null
        constraint group_enrollments_courses_id_fk
            references courses,
    group_pattern varchar(30) not null
);


create table if not exists code_reviews
(
    id             serial
        constraint code_reviews_pk
            primary key,
    submissions_id integer not null,
    author_id      integer not null,
    global_comment varchar,
    timestamp      bigint  not null
);


create table if not exists review_line_comments
(
    id              serial
        constraint review_line_comments_pk
            primary key,
    code_reviews_id integer     not null,
    line_number     integer     not null,
    message         varchar     not null,
    context         varchar     not null,
    file_name       varchar(80) not null
);

