class CsvParser {

  final bool comaAsDelimiter;
  final bool semicolonAsDelimiter;
  final bool spacesAsDelimiter;
  final bool tabAsDelimiter;
  final bool escapedStrings;
  final bool skipFirstRow;

  CsvParser({
    required this.comaAsDelimiter,
    required this.semicolonAsDelimiter,
    required this.spacesAsDelimiter,
    required this.tabAsDelimiter,
    required this.escapedStrings,
    required this.skipFirstRow,
  }) ;


  List<String> parseRow(String line) {
    List<String> result = List.empty(growable: true);
    String token = '';
    const Text = 0;
    const SQ = 1;
    const DQ = 2;
    int state = Text;

    for (int j=0; j<line.length; j++) {
      String sym = line[j];
      if (sym == '\'' && state==Text && escapedStrings)
        state = SQ;
      else if (sym == '"' && state==Text && escapedStrings)
        state = DQ;
      else if (sym == '\'' && state==SQ && escapedStrings)
        state = Text;
      else if (sym == '"' && state==DQ && escapedStrings)
        state = Text;
      else if (state == Text) {
        bool sep = false;
        sep |= (sym == ',' && comaAsDelimiter);
        sep |= (sym == ';' && semicolonAsDelimiter);
        sep |= (sym == '\t' && semicolonAsDelimiter);
        sep |= (sym == ' ' && spacesAsDelimiter);
        if (sep) {
          result.add(token);
          token = '';
        } else {
          token += sym;
        }
      }
    }
    if (token.length > 0)
      result.add(token);
    return result;
  }

  List<List<String>> parseTable(String data) {
    List<String> lines = data.split('\n');
    if (lines.length==1 && skipFirstRow)
      return List.empty();
    List<List<String>> table = List.empty(growable: true);
    for (int i=0; i<lines.length; i++) {
      if (skipFirstRow && i==0)
        continue;
      String line = lines[i].trim();
      if (line.isEmpty)
        continue;
      table.add(parseRow(lines[i]));
    }
    _normalizeColumnsCount(table);
    return table;
  }

  void _normalizeColumnsCount(List<List<String>> table) {
    int maxCols = 0;
    for (int i=0; i<table.length; i++) {
      maxCols = table[i].length > maxCols ? table[i].length : maxCols;
    }
    for (int i=0; i<table.length; i++) {
      while (table[i].length < maxCols) {
        table[i].add('');
      }
    }
  }

}