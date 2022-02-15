#!/usr/bin/env dart run
import '../lib/grader_main.dart' as lib;

main([List<String>? arguments]) => lib.serverMain(arguments==null? [] : arguments);
