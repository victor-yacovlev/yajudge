DART=dart
RM=rm -rf
INSTALL=install
USERADD=useradd -rmU -s /usr/sbin/nologin
MAKEDIRS=mkdir -p

PREFIX=/usr
ETC=/etc
USER=yajudge


first: all

all: content courses deadlines progress review sessions submissions users

content: .packages bin/yajudge-service-content
bin/yajudge-service-content: bin/yajudge_content_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/content_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-content bin/yajudge_content_service.dart

courses: .packages bin/yajudge-service-courses
bin/yajudge-service-courses: bin/yajudge_courses_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/content_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-courses bin/yajudge_courses_service.dart

deadlines: .packages bin/yajudge-service-deadlines
bin/yajudge-service-deadlines: bin/yajudge_deadlines_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/deadlines_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-deadlines bin/yajudge_deadlines_service.dart

progress: .packages bin/yajudge-service-progress
bin/yajudge-service-progress: bin/yajudge_progress_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/progress_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-progress bin/yajudge_progress_service.dart

review: .packages bin/yajudge-service-review
bin/yajudge-service-review: bin/yajudge_review_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/review_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-review bin/yajudge_review_service.dart

sessions: .packages bin/yajudge-service-sessions
bin/yajudge-service-sessions: bin/yajudge_sessions_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/sessions_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-sessions bin/yajudge_sessions_service.dart

submissions: .packages bin/yajudge-service-submissions
bin/yajudge-service-submissions: bin/yajudge_submissions_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/submissions_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-submissions bin/yajudge_submissions_service.dart

users: .packages bin/yajudge-service-users
bin/yajudge-service-users: bin/yajudge_users_service.dart $(wildcard lib/src/*.dart) $(wildcard lib/src/users_service/*.dart)
	$(DART) compile exe -o bin/yajudge-service-users bin/yajudge_users_service.dart

deps: .packages
.packages:
	$(DART) pub get


clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/yajudge-service-* || true


