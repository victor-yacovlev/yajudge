create table courses
(
    id                                           serial
        constraint courses_pk
            primary key,
    name                                         varchar(50)           not null,
    course_data                                  varchar(100)          not null,
    url_prefix                                   varchar(50)           not null,
    must_solve_all_required_problems_to_complete boolean default false,
    disable_review                               boolean default false,
    disable_defence                              boolean default true,
    need_update_deadlines                        boolean default false not null,
    description                                  varchar
);


create table submission_results
(
    id                          integer not null
        constraint submission_results_pk
            primary key,
    submission_protobuf_gzipped_base64 varchar   not null
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
    datetime          timestamp         not null,
    users_id          integer           not null
        constraint submissions_users_id_fk
            references users,
    courses_id        integer           not null
        constraint submissions_courses_id_fk
            references courses,
    problem_id        varchar(100)      not null,
    status            integer           not null,
    grading_status    integer default 0 not null,
    grader_name       varchar(100),
    style_error_log   varchar,
    compile_error_log varchar
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
    datetime       timestamp not null
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

create table lesson_schedules
(
    id                   serial
        constraint lesson_schedules_pk
            primary key,
    courses_id           integer           not null,
    datetime             timestamp         not null,
    repeat_count         integer default 1 not null,
    group_pattern        varchar(50),
    repeat_interval_days integer default 0 not null
);

create table submission_deadlines
(
    submissions_id integer not null
        constraint submission_deadlines_pk
            primary key,
    hard           timestamp,
    soft           timestamp
);

drop trigger if exists update_lesson_schedule on lesson_schedules;
drop trigger if exists insert_lesson_schedule on lesson_schedules;
drop trigger if exists delete_lesson_schedule on lesson_schedules;
create or replace function mark_course_deadlines_dirty() returns trigger
    language plpgsql
as $$
declare
    courses_id integer := 0;
begin
    if (tg_op = 'DELETE') then
        courses_id = old.courses_id;
    else
        courses_id = new.courses_id;
    end if;
    update courses set need_update_deadlines=true where id=courses_id;
    return new;
end
$$;

create trigger update_lesson_schedule after update on lesson_schedules
    for each row execute function mark_course_deadlines_dirty();

create trigger insert_lesson_schedule after insert on lesson_schedules
    for each row execute function mark_course_deadlines_dirty();

create trigger delete_lesson_schedule after delete on lesson_schedules
    for each row execute function mark_course_deadlines_dirty();
