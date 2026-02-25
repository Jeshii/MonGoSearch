import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'precedence_graph.dart';

class SearchStringHelper {
  static final Logger _log = Logger('SearchStringHelper');

  void configureLogging({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((rec) {
      debugPrint(
          '${rec.level.name}: ${rec.time}: ${rec.loggerName}: ${rec.message}');
    });
  }

  
  static bool checkValidity(String input) {
    String string = input.replaceAll(" ", "");
    return SearchStringHelper.getBalance(string) == 0 &&
        !string.contains(bracketPatterns);
  }

  static String simplifyResult(String input) {
    _log.fine("Simplify: " + input);
    Set<String> ands = input.split(andSepPattern).toSet();
    ands.remove("");
    String output = "";
    for (String and in ands) {
      Set<String> ors = and.split(orSepPattern).toSet();
      ors.remove("");
      for (String or in ors) {
        output += or;
        if (or != ors.last) {
          output += orChar;
        }
      }
      if (and != ands.last) {
        output += andChar;
      }
    }
    _log.fine("To: " + output);
    return output;
  }

  static int getBalance(String string) {
    int balance = 0;
    for (String char in string.characters) {
      if (char == '(') balance++;
      if (char == ')') balance--;
      if (balance < 0) break;
    }
    return balance;
  }

  static String _output = "";
  static String _modifier = "";
  static Set<Set<String>> _allTags = {};

  /// Strip comments from the input. A comment begins when one or more
  /// whitespace characters are followed by [marker] (default '#'). Everything
  /// from the first whitespace before the marker to the end of the line is
  /// removed. Operates line-by-line.
  static String stripComments(String input, {String marker = '#'}) {
    final lines = input.split(RegExp(r'\r?\n'));
    final out = <String>[];
    final pattern = RegExp(r'\s+' + RegExp.escape(marker));
    for (final line in lines) {
      final m = pattern.firstMatch(line);
      if (m != null) {
        out.add(line.substring(0, m.start));
      } else {
        out.add(line);
      }
    }
    return out.join('\n');
  }


  static String invertToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return t;

    // 1. Toggle negation if already negated
    if (t.startsWith('!')) return t.substring(1);

    // 2. Safely invert IVs or Star ratings if you prefer explicit visual ranges.
    // Matches a digit followed by an IV stat or star (e.g., "0attack" or "4*")
    final statRegExp = RegExp(r"^(\d+)(attack|defense|hp|\*)$", caseSensitive: false);
    final statMatch = statRegExp.firstMatch(t);
    
    if (statMatch != null) {
      final n = int.parse(statMatch.group(1)!);
      final suffix = statMatch.group(2)!;
      
      // In PoGo, stats and stars max out at 4. 
      if (n == 0) return "1-4$suffix";
      if (n == 4) return "0-3$suffix";
      // (If n is 1, 2, or 3, it's safer to just fall through to the '!' prefix)
    }

    // 3. For Pokédex, CP, distance, and general terms, `!token` is the safest.
    // E.g., "150" -> "!150", "shiny" -> "!shiny", "0-1attack" -> "!0-1attack"
    return "!" + t;
  }

  static String invertGroupToPoGoString(String keepGroup) {
    // 1. Clean the input and remove outer parentheses. Also detect a leading
    // '!' directly before parentheses (e.g. "!(A,B)") and treat it as
    // negating the whole group so De Morgan can be applied correctly.
    String cleanGroup = keepGroup.trim();
    bool negatedWhole = false;
    if (cleanGroup.startsWith('!')) {
      String rest = cleanGroup.substring(1).trim();
      if (rest.startsWith('(') && rest.endsWith(')')) {
        negatedWhole = true;
        cleanGroup = rest.substring(1, rest.length - 1);
      }
    } else if (cleanGroup.startsWith('(') && cleanGroup.endsWith(')')) {
      cleanGroup = cleanGroup.substring(1, cleanGroup.length - 1);
    }

    // 2. Parse the group into a List of Lists of inverted tokens
    // E.g., "4a,4d & 4a,4h" -> [ ["!4a", "!4d"], ["!4a", "!4h"] ]
    List<String> andGroups = cleanGroup.split('&');
    List<List<String>> invertedGroups = [];

    for (String andGroup in andGroups) {
      List<String> orTokens = andGroup.split(',');
      List<String> invertedTokens = [];
      for (String token in orTokens) {
        String t = token.trim();
        if (t.isNotEmpty) {
          // Run your previously fixed invertToken() function here
          invertedTokens.add(invertToken(t)); 
        }
      }
      if (invertedTokens.isNotEmpty) {
        invertedGroups.add(invertedTokens);
      }
    }

    // 3. Cartesian Product (Converts the logic into PoGo's comma-first format)
    List<String> combinations = [""];
    for (List<String> group in invertedGroups) {
      List<String> newCombinations = [];
      for (String combination in combinations) {
        for (String token in group) {
          if (combination.isEmpty) {
            newCombinations.add(token);
          } else {
            newCombinations.add(combination + "," + token);
          }
        }
      }
      combinations = newCombinations;
    }

    // 4. Simplify: deduplicate tokens within each OR-combination
    List<Set<String>> finalSets = [];
    for (String combo in combinations) {
      finalSets.add(combo.split(',').map((e) => e.trim()).toSet());
    }

    // 5. Boolean Absorption (Crucial for keeping the string short!)
    // In logic, (A) AND (A OR B) simplifies to just (A).
    // This removes combinations that are supersets of other combinations.
    List<Set<String>> absorbedSets = [];
    for (int i = 0; i < finalSets.length; i++) {
      bool isSuperset = false;
      for (int j = 0; j < finalSets.length; j++) {
        if (i == j) continue;
        // If Set i contains everything in Set j, Set i is redundant.
        if (finalSets[i].containsAll(finalSets[j])) {
          // Tie-breaker to ensure we don't delete identical sets simultaneously
          if (finalSets[i].length > finalSets[j].length || i > j) {
            isSuperset = true;
            break;
          }
        }
      }
      if (!isSuperset) {
        absorbedSets.add(finalSets[i]);
      }
    }

    // 6. Format and join the final groups with '&'
    List<String> outputGroups = [];
    for (Set<String> set in absorbedSets) {
      List<String> sortedTokens = set.toList()..sort();
      outputGroups.add(sortedTokens.join(','));
    }

    // If the entire group was negated (NOT ( ... )), the algorithm above
    // already produced the correct inverted tokens (e.g. '!A' and '!B'), and
    // they should be ANDed together — joining with '&' is correct.
    return outputGroups.join('&');
  }

  static String generateFullTrashString(String fullInput) {
    // Split the massive input block by `),` or newlines to isolate each group
    List<String> keepGroups = fullInput.split(RegExp(r'\),\s*|\r?\n'));
    List<String> trashGroups = [];

    for (String group in keepGroups) {
      if (group.trim().isNotEmpty) {
        // Process each group using the new Cartesian function
        trashGroups.add(invertGroupToPoGoString(group));
      }
    }

    // Because AND runs last in PoGo, safely chain all the resulting trash groups together
    return trashGroups.join('&');
  }

  /// You can only run 1 of this at a time!
  /// It uses static members to save on memory!
  static String getRecursiveMethod(Set<Set<String>> allTags, String modifier) {
    _output = "";
    _modifier = modifier;
    _allTags = allTags;
    _generateRecursive("", allTags.length - 1);
    return _output;
  }

  static void _generateRecursive(String current, int level) {
    if (level < 0) {
      _output += andChar + _modifier + current;
      _log.finer("leaf " + current);
      return;
    }
    _allTags.elementAt(level).forEach((element) {
      _generateRecursive(current + orChar + element, level - 1);
    });
  }
  // Many thanks to my Friend Martin who helped me with this recursive solution!

  static String invertGroup(String group) {
    // 1. Clean outer parentheses
    String cleanGroup = group.trim();
    // Accept leading NOT (case-insensitive) as equivalent to '!'.
    // Examples handled: "NOT (A,B)", "NOT(A)", "not A".
    if (cleanGroup.toUpperCase().startsWith('NOT')) {
      String rest = cleanGroup.substring(3).trim();
      // If the NOT applies to a parenthesized group, delegate to the
      // De Morgan-aware helper which produces the correct inverted form.
      if (rest.startsWith('(') && rest.endsWith(')')) {
        return invertGroupToPoGoString('!' + rest);
      }
      // Otherwise convert the leading NOT into a '!' and continue processing.
      cleanGroup = '!' + rest;
    }

    // If we now have a leading '!' and it's applied to a parenthesized
    // expression (e.g. "!(A,B)"), delegate to the De Morgan-aware helper.
    if (cleanGroup.startsWith('!')) {
      String rest = cleanGroup.substring(1).trim();
      if (rest.startsWith('(') && rest.endsWith(')')) {
        return invertGroupToPoGoString(cleanGroup);
      }
      // Otherwise leave `cleanGroup` as-is and fall through to token parsing.
    } else if (cleanGroup.startsWith('(') && cleanGroup.endsWith(')')) {
      cleanGroup = cleanGroup.substring(1, cleanGroup.length - 1);
    }

    // 2. Split into AND groups (e.g. "4a,4d" and "4a,4h")
    // Note: Use your existing andSepPattern/orSepPattern if defined globally
    List<String> andGroups = cleanGroup.split(RegExp(r'&'));
    
    Set<Set<String>> allTags = {};

    for (String andGroup in andGroups) {
      // 3. Split into OR tokens
      List<String> orTokens = andGroup.split(RegExp(r','));
      
      Set<String> invertedTokens = {};
      for (String token in orTokens) {
        String t = token.trim();
        if (t.isNotEmpty) {
          // Use the safely updated invertToken from our previous step
          invertedTokens.add(invertToken(t)); 
        }
      }
      if (invertedTokens.isNotEmpty) {
        allTags.add(invertedTokens);
      }
    }

    // 4. Distribute using your existing recursive method!
    // This safely converts the inverted logic back into a PoGo-readable format
    String result = getRecursiveMethod(allTags, "");

    // 5. Use your existing simplifyResult to magically clean up the syntax
    // It naturally strips the formatting generated by getRecursiveMethod and deduplicates tokens
    return simplifyResult(result);
  }

}
