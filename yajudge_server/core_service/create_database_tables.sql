drop table if exists users cascade;
drop table if exists sessions cascade;
drop table if exists courses cascade;
drop table if exists enrollments cascade;


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
    course_data varchar(100) not null,
    url_prefix  varchar(50)  not null
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

