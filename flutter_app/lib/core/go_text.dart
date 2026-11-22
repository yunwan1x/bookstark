/// Match Go strings.TrimSpace without treating U+FEFF (BOM) as whitespace.
/// Used for Go-backed asset validation; never normalizes a credential payload.
String trimGoSpace(String value) {
  bool space(int unit) =>
      unit >= 0x09 && unit <= 0x0d ||
      unit == 0x20 ||
      unit == 0x85 ||
      unit == 0xa0 ||
      unit == 0x1680 ||
      unit >= 0x2000 && unit <= 0x200a ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202f ||
      unit == 0x205f ||
      unit == 0x3000;
  var start = 0;
  var end = value.length;
  while (start < end && space(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && space(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}
