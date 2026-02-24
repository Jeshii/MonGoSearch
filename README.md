# MonGoSearch
A cross platform project aimed to bring more complex search options to Pokemon Go users

## Operators

MonGoSearch accepts a few simple boolean operators and conventions when building Pokemon Go search strings:

- OR: use `,` or the word `OR` (case-insensitive) to separate alternatives.
- AND: use `&` or the word `AND` (case-insensitive) to join groups.
- NOT: use `!` or the word `NOT` (case-insensitive) to negate a token or group.
- Parentheses `()` may be used to group expressions.
- Comments can be added with `#` (anything after a space followed by `#` on a line is ignored).

Example: `A,B & C,D` is interpreted as `(A OR B) AND (C OR D)` (Pokémon GO logic).
