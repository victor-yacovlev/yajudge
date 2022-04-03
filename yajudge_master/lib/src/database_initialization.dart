import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'master_service.dart';
import 'assets_loader.dart';
import 'dart:io' as io;

final tablesRequired = {
  'enrollments', 'users', 'sessions', 'submission_files',
  'submission_results', 'submissions', 'courses'
};

Future<bool> checkTablesExists(MasterService masterService) async {
  final query = '''
  select table_name from information_schema.tables where table_schema='public';
  ''';
  final tablesRows = await masterService.connection.query(query);
  Set<String> tablesExists = {};
  for (final row in tablesRows) {
    String tableName = row.single;
    tablesExists.add(tableName);
  }
  final db = masterService.connection;
  final dbName = '${db.host}:${db.port}/${db.databaseName}';
  for (final requiredTable in tablesRequired) {
    if (!tablesExists.contains(requiredTable)) {
      Logger.root.shout('table $requiredTable not exists in database $dbName');
      return false;
    }
  }
  return true;
}

Future initializeDatabase(MasterService masterService) async {
  final db = masterService.connection;
  final dbName = '${db.host}:${db.port}/${db.databaseName}';
  print('This will create new empty database $dbName');
  print('WARNING: if database exists it will be dropped!');
  print('Type "yes" to confirm this action: ');
  final answer = io.stdin.readLineSync()!.trim().toLowerCase();
  if (answer != 'yes') {
    print('Dangerous operation not approved by user. Exiting');
    io.exit(1);
  }

  // Drop all tables if exists
  for (final tableName in tablesRequired) {
    await db.execute('drop table if exists $tableName cascade');
    print('Dropped table $tableName in $dbName');
  }

  // Create tables
  final sqlStatements = assetsLoader.fileAsString('yajudge-db-schema.sql');
  assert (sqlStatements.trim().isNotEmpty);
  try {
    await db.execute(sqlStatements);
    print('Created new database schema in $dbName');
  }
  catch (e) {
    final message = 'Cant initialize $dbName: $e';
    print(message);
    io.exit(1);
  }
}

Future createAdministratorUser(MasterService masterService, String email, String password) async {
  final db = masterService.connection;
  final existingUserRows = await db.query(
    '''
    select email from users where email=@email 
    ''',
    substitutionValues: {
      'email': email
    },
  );
  if (existingUserRows.length > 0) {
    // update existing user password
    await db.execute(
      '''
      update users set password=@password where email=@email
      ''',
      substitutionValues: {
        'email': email,
        'password': '='+password,
      }
    );
  }
  else {
    // create new user
    await db.execute(
        '''
        insert into users(first_name,last_name,email,password,default_role) values('Administrator','',@email,@password,@role)
        ''',
        substitutionValues: {
          'email': email,
          'password': '=' + password,
          'role': Role.ROLE_ADMINISTRATOR.value,
        }
    );
  }
}

Future createCourseEntry(
    MasterService masterService,
    String courseTitle, String courseData, String courseUrl,
    [bool noTeacherMode = true,
    bool mustSolveAllProblemsToComplete = false])
{
  final db = masterService.connection;
  final coursesRoot = masterService.courseManagementService.locationProperties.coursesRoot;
  final coursePath = '$coursesRoot/$courseData';

  if (!io.Directory(coursePath).existsSync()) {
    final message = 'course directory not exists:  $coursePath';
    print(message);
    Logger.root.shout(message);
    io.exit(1);
  }

  return db.execute(
    '''
    insert into courses(name,course_data,url_prefix,no_teacher_mode,must_solve_all_required_problems_to_complete)
    values(@name,@data,@url,@no_teacher,@must_solve)
    ''',
    substitutionValues: {
      'name': courseTitle,
      'data': courseData,
      'url': courseUrl,
      'no_teacher': noTeacherMode,
      'must_solve': mustSolveAllProblemsToComplete,
    },
  );
}