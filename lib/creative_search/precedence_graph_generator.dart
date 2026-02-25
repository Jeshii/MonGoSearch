import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'precedence_graph.dart';
import 'search_string_helper.dart';

class PGraphGenerator {
  static final Logger _log = Logger('PGraphGenerator');

  static void configureLogging({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((rec) {
      debugPrint(
          '${rec.level.name}: ${rec.time}: ${rec.loggerName}: ${rec.message}');
    });
  }

  static PrecedenceNode generateFromString(String searchString) {
    Characters characters = (andChar + searchString).characters;
    _log.fine('generating from: ${characters.string}');

    if (characters.isEmpty) return simpleGenerate(""); //ends of recursion
    if (!characters.contains("(")) return simpleGenerate(characters.string);

    int? openLB;
    int lastRB = -1;
    int depth = 0;
    Operands opType;
    PrecedenceNode root = simpleGenerate("");

    for (int i = 0; i < characters.length; i++) {
      if (characters.elementAt(i) == '(') {
        if (openLB == null) {
          openLB = i;
          // Determine the separator before this group. The separator may be
          // separated by whitespace (e.g. "NOT (...") so extract a small
          // window around the expected position.
          opType = opFromString(_sepForIndex(characters, lastRB + 1, before: false));
          // If there's a '!' immediately before the '(', exclude it from
          // the simpleGenerate range so it doesn't become a stray leaf token.
          int simpleEnd = openLB;
          // If there's a '!' or textual 'NOT' immediately before the '(',
          // exclude it from the simpleGenerate range so it doesn't become
          // a stray leaf token.
          int prevTokenStart = _prevNegationTokenStart(
              characters, openLB - 1, lowerBound: lastRB + 1);
          if (prevTokenStart >= 0) {
            simpleEnd = prevTokenStart; // exclude the negation token
          }
          _log.fine('Simple from ${lastRB + 2} to $i');
          registerToAndRoot(
              root,
              simpleGenerate(characters.getRange(lastRB + 1, simpleEnd).string),
              opType);
        }
        depth++;
      }
      if (characters.elementAt(i) == ')') {
        depth--;
      }
      if (openLB != null && depth == 0) {
        lastRB = i;
        opType = opFromString(_sepForIndex(characters, openLB - 1, before: true));
        if (debugLevel > 0) {
          _log.fine('Generate() from ${openLB + 1} to $lastRB');
        }
        // Detect if the group was negated by a leading '!' or textual 'NOT'
        int prevNegStart = _prevNegationTokenStart(
            characters, openLB - 1, lowerBound: lastRB + 1);
        bool negated = (prevNegStart >= 0);
        PrecedenceNode groupNode = generateFromString(characters.getRange(openLB + 1, lastRB).string);
        if (negated) {
          groupNode = _negateNode(groupNode);
        }
        registerToAndRoot(root, groupNode, opType);
        openLB = null;
      }
    }
    if (lastRB != characters.length - 1) {
      if (debugLevel > 0) {
        _log.fine('Simple tail from ${lastRB + 1} to ${characters.length}');
      }
      opType = opFromString(_sepForIndex(characters, lastRB + 1, before: false));
      registerToAndRoot(
          root,
          simpleGenerate(
              characters.getRange(lastRB + 1, characters.length).string),
          opType);
    }
    return root;
  }

  static int _prevNonWhitespaceIndex(Characters chars, int start, {int lowerBound = 0}) {
    int i = start;
    while (i >= lowerBound) {
      if (chars.elementAt(i).trim().isNotEmpty) return i;
      i--;
    }
    return -1;
  }

  // Return the index of the first character of a negation token that ends
  // at or before `start`, or -1 if none. Recognizes '!' and textual 'NOT'
  // (case-insensitive). The returned index points to the start of the token
  // (for '!' it's the same as the end).
  static int _prevNegationTokenStart(Characters chars, int start, {int lowerBound = 0}) {
    int prev = _prevNonWhitespaceIndex(chars, start, lowerBound: lowerBound);
    if (prev < 0) return -1;
    if (chars.elementAt(prev) == '!') return prev;
    // Check for 'NOT' ending at prev (3 characters). Ensure we don't go
    // before the lowerBound.
    int candidateStart = prev - 2;
    if (candidateStart < lowerBound) return -1;
    String candidate = chars.getRange(candidateStart, prev + 1).string;
    if (candidate.toUpperCase() == 'NOT') return candidateStart;
    return -1;
  }

  static PrecedenceNode _negateNode(PrecedenceNode node) {
    if (node is PrecedenceLeaf) {
      // Toggle the negation flag instead of replacing the content string.
      return PrecedenceLeaf(node.content, null, negated: !node.negated);
    }
    if (node is OperandNode) {
      Operands newOp = node.operand == Operands.and ? Operands.or : Operands.and;
      OperandNode newNode = OperandNode.empty(newOp);
      for (PrecedenceNode child in node.children) {
        PrecedenceNode negChild = _negateNode(child);
        newNode.register(negChild);
      }
      return newNode;
    }
    return node;
  }

  // Extract a short separator window around `index`. If `before` is true,
  // we extract characters looking backward (useful for positions just before
  // an opening parenthesis). If false, we look forward (useful for tails).
  static String _sepForIndex(Characters chars, int index, {bool before = true}) {
    if (chars.isEmpty) return '';
    if (index < 0) index = 0;
    if (index >= chars.length) index = chars.length - 1;

    if (before) {
      int i = index;
      // Move left past whitespace
      while (i >= 0 && chars.elementAt(i).trim().isEmpty) i--;
      int start = i - 3;
      if (start < 0) start = 0;
      return chars.getRange(start, i + 1).string;
    } else {
      int i = index;
      // Move right past whitespace
      while (i < chars.length && chars.elementAt(i).trim().isEmpty) i++;
      int end = i + 3;
      if (end >= chars.length) end = chars.length - 1;
      return chars.getRange(i, end + 1).string;
    }
  }

  static void registerToAndRoot(
      PrecedenceNode root, PrecedenceNode node, Operands opType) {
    if (opType == Operands.and || root.children.isEmpty) {
      // Check this if something is incorrect
      root.register(OperandNode.empty(Operands.or));
    }
    root.children.last.register(node);
  }

  static PrecedenceNode simpleGenerate(String string) {
    if (string.characters.isEmpty) {
      PrecedenceNode? root = OperandNode.empty(Operands.and);
      root.register(OperandNode.empty(Operands.or));
      return root;
    }
    _log.fine('simple from: $string');

    PrecedenceNode root = OperandNode.empty(Operands.and);
    for (String ands in string.split(andSepPattern)) {
      if (ands.isNotEmpty) {
        OperandNode or = OperandNode(Operands.or, null, root);
        List<String> ors = ands.split(orSepPattern);
        ors.removeWhere((element) => element == "");
        if (ors.isNotEmpty) {
          root.children.add(or);
          PrecedenceLeaf.fromStrings(ors, or);
        }
      }
    }
    return root;
  }
}
