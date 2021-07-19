drop table if exists users cascade;
drop table if exists sessions cascade;
drop table if exists courses cascade;
drop table if exists enrollments cascade;
drop table if exists review_comments cascade;
drop table if exists code_reviews cascade;
drop table if exists submission_files cascade;
drop table if exists submissions cascade;


create table users
(
    id           serial                not null
        constraint users_pk
            primary key,
    password     varchar(128)          not null,
    first_name   varchar(50)           not null,
    last_name    varchar(50)           not null,
    mid_name     varchar(50),
    email        varchar(50),
    group_name   varchar(30),
    default_role integer default 0     not null,
    disabled     boolean default false not null
);

create table sessions
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

create table courses
(
    id          serial       not null
        constraint courses_pk
            primary key,
    name        varchar(50)  not null,
    course_data varchar(50) not null
);

create table enrollments
(
    id         serial  not null
        constraint enrollments_pk
            primary key,
    courses_id integer not null
        constraint enrollments_courses_id_fk
            references courses,
    users_id   integer not null
        constraint enrollments_users_id_fk
            references users,
    role   integer not null
);


create table submissions
(
    id            integer                                        not null
        constraint submissions_pk
            primary key,
    problems_id   integer                                        not null
        constraint submissions_problems_id_fk
            references problems,
    status        integer          default 0                     not null,
    grader_score  double precision default 0                     not null,
    grader_name   varchar          default ''::character varying not null,
    grader_output varchar          default ''::character varying not null,
    grader_errors varchar          default ''::character varying not null
);

create table submission_files
(
    id             integer                                             not null
        constraint submission_files_pk
            primary key,
    submissions_id integer                                             not null
        constraint submission_files_submissions_id_fk
            references submissions,
    name           varchar                                             not null,
    content_type   varchar(30) default 'text/plain'::character varying not null,
    data           bytea                                               not null
);

create table code_reviews
(
    id             integer                               not null
        constraint code_reviews_pk
            primary key,
    author_id      integer                               not null
        constraint code_reviews_users_id_fk
            references users,
    global_comment varchar default ''::character varying not null,
    submissions_id integer                               not null
        constraint code_reviews_submissions_id_fk
            references submissions
);

create table review_comments
(
    id                  integer           not null
        constraint review_comments_pk
            primary key,
    code_reviews_id     integer           not null
        constraint review_comments_code_reviews_id_fk
            references code_reviews,
    submission_files_id integer           not null
        constraint review_comments_submission_files_id_fk
            references submission_files,
    start_position      integer default 0 not null,
    end_position        integer default 0 not null
);
