create table if not exists courses
(
    id                                           serial primary key,
    name                                         varchar(50)           not null,
    course_data                                  varchar(100)          not null,
    url_prefix                                   varchar(50)           not null,
    must_solve_all_required_problems_to_complete boolean default false,
    disable_review                               boolean default false,
    disable_defence                              boolean default true,
    need_update_deadlines                        boolean default false not null,
    description                                  varchar
);


create table if not exists submission_results
(
    id                                  serial  primary key,
    submission_protobuf_gzipped_base64  varchar   not null
);


create table if not exists users
(
    id           serial primary key,
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
    id                                           serial primary key,
    courses_id    integer                                                     not null,
    users_id      integer                                                     not null,
    role          integer                                                     not null,
    group_pattern varchar(30) default ''::character varying                   not null
);


create table if not exists sessions
(
    cookie   varchar(64) not null primary key,
    start    timestamp   not null,
    users_id integer     not null
);


create table if not exists submissions
(
    id                serial primary key,
    datetime          timestamp         not null,
    users_id          integer           not null,
    courses_id        integer           not null,
    problem_id        varchar(100)      not null,
    status            integer           not null,
    grading_status    integer default 0 not null,
    grader_name       varchar(100),
    style_error_log   varchar,
    compile_error_log varchar
);


create table if not exists submission_files
(
    id                                           serial primary key,
    file_name      varchar(30)                                                  not null,
    content        varchar                                                      not null,
    submissions_id integer                                                      not null
);


create table if not exists group_enrollments
(
    id            serial primary key,
    courses_id    integer     not null,
    group_pattern varchar(30) not null
);


create table if not exists code_reviews
(
    id             serial primary key,
    submissions_id integer not null,
    author_id      integer not null,
    global_comment varchar,
    datetime       timestamp not null
);


create table if not exists review_line_comments
(
    id              serial      primary key,
    code_reviews_id integer     not null,
    line_number     integer     not null,
    message         varchar     not null,
    context         varchar     not null,
    file_name       varchar(80) not null
);

create table if not exists lesson_schedules
(
    id                   serial            primary key,
    courses_id           integer           not null,
    datetime             timestamp         not null,
    repeat_count         integer default 1 not null,
    group_pattern        varchar(50),
    repeat_interval_days integer default 0 not null
);

create table if not exists submission_deadlines
(
    submissions_id integer not null primary key,
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
