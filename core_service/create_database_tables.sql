drop table if exists users cascade;
drop table if exists sessions cascade;
drop table if exists capabilities cascade;
drop table if exists roles cascade;
drop table if exists roles_capabilities cascade;
drop table if exists courses cascade;
drop table if exists enrollments cascade;

create table capabilities
(
    id           serial      not null
        constraint capabilities_pk
            primary key,
    subsystem    varchar(30) not null,
    method       varchar(40) not null
);

create table roles
(
    id   serial      not null
        constraint roles_pk
            primary key,
    name varchar(50) not null
);

create table roles_capabilities
(
    roles_id        integer not null
        constraint roles_capabilities_capabilities_id_fk
            references capabilities
            on delete restrict
        constraint roles_capabilities_roles_id_fk
            references roles
            on delete restrict,
    capabilities_id integer not null,
    constraint roles_capabilities_pk
        primary key (roles_id, capabilities_id)
);


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
    default_role integer
        constraint users_roles_id_fk
            references roles,
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
    id   serial      not null
        constraint courses_pk
            primary key,
    name varchar(50) not null
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
    roles_id   integer not null
        constraint enrollments_roles_id_fk
            references roles
);
