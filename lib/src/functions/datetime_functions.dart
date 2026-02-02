import '../errors/jsonata_exception.dart';
import '../evaluator/environment.dart';
import '../utils/undefined.dart';

/// Date/Time functions for JSONata.
class DateTimeFunctions {
  /// The timestamp captured at the start of expression evaluation.
  /// All invocations of $now() and $millis() within an evaluation
  /// will return the same timestamp value.
  static int? _evaluationTimestamp;

  /// Resets the evaluation timestamp (called at start of each evaluation).
  static void resetTimestamp() {
    _evaluationTimestamp = null;
  }

  /// Gets or initializes the evaluation timestamp.
  static int get evaluationTimestamp {
    _evaluationTimestamp ??= DateTime.now().millisecondsSinceEpoch;
    return _evaluationTimestamp!;
  }

  /// Number words for word-based number parsing.
  static const _numberWordsList = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty',
    'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand', 'million', 'billion',
    'zeroth', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth',
    'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth', 'fifteenth',
    'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth', 'twentieth', 'thirtieth',
    'fortieth', 'fiftieth', 'sixtieth', 'seventieth', 'eightieth', 'ninetieth',
    'hundredth', 'thousandth', 'millionth', 'billionth', 'and'
  ];

  /// Regex pattern for matching word-based numbers.
  /// Matches only known number words, not arbitrary words like month names.
  static final String _numberWordsRegex = _buildNumberWordsRegex();

  static String _buildNumberWordsRegex() {
    // Build alternation of all number words
    final words = _numberWordsList.join('|');
    // Pattern: one or more number words (optionally hyphenated), separated by spaces/commas
    // e.g., "twenty-first", "one thousand, nine hundred and eighty-four"
    return '(?:(?:$words)(?:-(?:$words))?(?:[,\\s]+)?)+';
  }

  /// Registers all date/time functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$now', _now);
    env.registerFunction(r'$millis', _millis);
    env.registerFunction(r'$fromMillis', _fromMillis);
    env.registerFunction(r'$toMillis', _toMillis);
  }

  /// $now([picture [, timezone]]) - Returns current timestamp.
  static dynamic _now(List<dynamic> args, dynamic input, Environment env) {
    final millis = evaluationTimestamp;
    if (args.isEmpty) {
      return _formatIso8601(millis);
    }
    // With picture string
    final picture = args[0];
    if (isUndefined(picture)) return undefined;
    if (picture is! String) return undefined;
    final timezone = args.length > 1 ? args[1] : null;
    return _formatWithPicture(millis, picture, timezone);
  }

  /// $millis() - Returns current timestamp as milliseconds since Unix epoch.
  static dynamic _millis(List<dynamic> args, dynamic input, Environment env) {
    return evaluationTimestamp;
  }

  /// $fromMillis(number [, picture [, timezone]]) - Format milliseconds to string.
  static dynamic _fromMillis(
      List<dynamic> args, dynamic input, Environment env) {
    // Use context if no args provided
    final millis = args.isNotEmpty ? args[0] : input;
    if (isUndefined(millis)) return undefined;
    if (millis is! num) return undefined;

    final millisInt = millis.toInt();
    final timezone = args.length > 2 ? args[2] : null;

    // No picture string or null/undefined picture - return ISO 8601 format
    if (args.length < 2 || isUndefined(args[1]) || args[1] == null) {
      // Check if timezone is provided
      if (timezone != null && timezone is String && timezone.isNotEmpty) {
        return _formatIso8601WithTimezone(millisInt, timezone);
      }
      return _formatIso8601(millisInt);
    }

    final picture = args[1];
    if (picture is! String) {
      // Invalid picture type but timezone may still be provided
      if (timezone != null && timezone is String && timezone.isNotEmpty) {
        return _formatIso8601WithTimezone(millisInt, timezone);
      }
      return undefined;
    }

    if (picture.isEmpty) {
      // Empty picture with timezone - format ISO with timezone offset
      if (timezone != null && timezone is String && timezone.isNotEmpty) {
        return _formatIso8601WithTimezone(millisInt, timezone);
      }
      return _formatIso8601(millisInt);
    }

    return _formatWithPicture(millisInt, picture, timezone);
  }

  /// $toMillis(timestamp [, picture]) - Parse timestamp to milliseconds.
  static dynamic _toMillis(
      List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final timestamp = args[0];
    if (isUndefined(timestamp)) return undefined;
    if (timestamp is! String) return undefined;

    // No picture string - parse ISO 8601 format
    if (args.length < 2 || isUndefined(args[1]) || args[1] == null) {
      return _parseIso8601(timestamp);
    }

    final picture = args[1];
    if (picture is! String) return undefined;

    return _parseWithPicture(timestamp, picture);
  }

  /// Formats milliseconds as ISO 8601 string.
  static String _formatIso8601(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    final ms = (millis % 1000).abs().toString().padLeft(3, '0');
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${ms}Z';
  }

  /// Formats milliseconds as ISO 8601 string with specified timezone.
  static String _formatIso8601WithTimezone(int millis, String timezone) {
    // Parse timezone offset (reuses _parseTimezoneOffset defined later)
    final offsetMinutes = _parseTimezoneOffsetInternal(timezone);

    // If offset is 0, use standard UTC format with 'Z'
    if (offsetMinutes == 0) {
      return _formatIso8601(millis);
    }

    // Adjust time by timezone offset
    final adjustedMillis = millis + offsetMinutes * 60 * 1000;
    final dt = DateTime.fromMillisecondsSinceEpoch(adjustedMillis, isUtc: true);
    final ms = (millis % 1000).abs().toString().padLeft(3, '0');

    // Format timezone offset string
    final sign = offsetMinutes >= 0 ? '+' : '-';
    final absOffset = offsetMinutes.abs();
    final hours = absOffset ~/ 60;
    final mins = absOffset % 60;
    final tzStr = '$sign${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';

    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '$ms$tzStr';
  }

  /// Parses timezone offset string for internal use.
  static int _parseTimezoneOffsetInternal(String timezone) {
    if (timezone.isEmpty) return 0;
    if (timezone.toUpperCase() == 'Z') return 0;
    final sign = timezone.startsWith('-') ? -1 : 1;
    final offset = timezone.replaceAll(RegExp(r'[+-]'), '');
    if (offset.length < 2) return 0;
    final hours = int.parse(offset.substring(0, 2));
    final minutes = offset.length >= 4 ? int.parse(offset.substring(2, 4)) : 0;
    return sign * (hours * 60 + minutes);
  }

  /// Parses ISO 8601 timestamp string to milliseconds.
  static dynamic _parseIso8601(String timestamp) {
    // Try various ISO 8601 formats
    final patterns = [
      // Full ISO 8601 with timezone
      RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})([+-]\d{4}|Z)$'),
      RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-]\d{4}|Z)$'),
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})$'),
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$'),
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$'),
      RegExp(r'^(\d{4})$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(timestamp);
      if (match != null) {
        return _parseIso8601Match(match, timestamp);
      }
    }

    // Invalid format
    throw JsonataException('D3110', 'Invalid ISO 8601 format: $timestamp',
        position: 0);
  }

  static int _parseIso8601Match(RegExpMatch match, String timestamp) {
    final groups = match.groups(
        List.generate(match.groupCount, (i) => i + 1));
    final year = int.parse(groups[0]!);
    final month = groups.length > 1 && groups[1] != null
        ? int.parse(groups[1]!)
        : 1;
    final day = groups.length > 2 && groups[2] != null
        ? int.parse(groups[2]!)
        : 1;
    final hour = groups.length > 3 && groups[3] != null
        ? int.parse(groups[3]!)
        : 0;
    final minute = groups.length > 4 && groups[4] != null
        ? int.parse(groups[4]!)
        : 0;
    final second = groups.length > 5 && groups[5] != null
        ? int.parse(groups[5]!)
        : 0;
    int millisecond = 0;
    String? tz;

    // Check if we have milliseconds and/or timezone
    for (int i = 6; i < groups.length; i++) {
      final g = groups[i];
      if (g == null) continue;
      if (g.startsWith('+') || g.startsWith('-') || g == 'Z') {
        tz = g;
      } else if (RegExp(r'^\d+$').hasMatch(g)) {
        millisecond = int.parse(g.padRight(3, '0').substring(0, 3));
      }
    }

    var dt = DateTime.utc(year, month, day, hour, minute, second, millisecond);

    // Apply timezone offset
    if (tz != null && tz != 'Z') {
      final sign = tz.startsWith('-') ? 1 : -1;
      final offsetHours = int.parse(tz.substring(1, 3));
      final offsetMinutes = int.parse(tz.substring(3, 5));
      dt = dt.add(Duration(
        hours: sign * offsetHours,
        minutes: sign * offsetMinutes,
      ));
    }

    return dt.millisecondsSinceEpoch;
  }

  /// Formats milliseconds using XPath/XQuery picture string.
  static dynamic _formatWithPicture(
      int millis, String picture, dynamic timezone) {
    // Parse timezone offset
    int tzOffsetMinutes = 0;
    if (timezone != null && timezone is String && timezone.isNotEmpty) {
      tzOffsetMinutes = _parseTimezoneOffset(timezone);
    }

    // Apply timezone offset to get local time
    final dt = DateTime.fromMillisecondsSinceEpoch(
      millis + tzOffsetMinutes * 60 * 1000,
      isUtc: true,
    );

    final result = StringBuffer();
    var i = 0;

    while (i < picture.length) {
      final char = picture[i];

      if (char == '[') {
        if (i + 1 < picture.length && picture[i + 1] == '[') {
          // Escaped opening bracket
          result.write('[');
          i += 2;
          continue;
        }
        // Find closing bracket
        final closeBracket = picture.indexOf(']', i);
        if (closeBracket < 0) {
          throw JsonataException('D3135',
              'Picture string contains unclosed bracket at position $i',
              position: 0);
        }
        final component = picture.substring(i + 1, closeBracket);
        // Remove whitespace from component
        final cleanComponent = component.replaceAll(RegExp(r'\s'), '');
        result.write(_formatComponent(
            cleanComponent, dt, millis, tzOffsetMinutes, timezone));
        i = closeBracket + 1;
      } else if (char == ']') {
        if (i + 1 < picture.length && picture[i + 1] == ']') {
          // Escaped closing bracket
          result.write(']');
          i += 2;
          continue;
        }
        result.write(char);
        i++;
      } else {
        result.write(char);
        i++;
      }
    }

    return result.toString();
  }

  /// Parses timezone offset string (e.g., "+0530", "-0500") to minutes.
  static int _parseTimezoneOffset(String timezone) {
    if (timezone.isEmpty) return 0;
    final sign = timezone.startsWith('-') ? -1 : 1;
    final offset = timezone.replaceAll(RegExp(r'[+-]'), '');
    if (offset.length < 2) return 0;
    final hours = int.parse(offset.substring(0, 2));
    final minutes = offset.length >= 4 ? int.parse(offset.substring(2, 4)) : 0;
    return sign * (hours * 60 + minutes);
  }

  /// Formats a single component from the picture string.
  static String _formatComponent(String component, DateTime dt, int millis,
      int tzOffsetMinutes, dynamic timezone) {
    if (component.isEmpty) return '';

    final specifier = component[0];
    final presentation = component.length > 1 ? component.substring(1) : '';

    switch (specifier) {
      case 'Y': // Year
        return _formatYear(dt.year, presentation);
      case 'M': // Month
        return _formatMonth(dt.month, presentation);
      case 'D': // Day of month
        return _formatNumber(dt.day, presentation);
      case 'd': // Day of year
        return _formatNumber(_dayOfYear(dt), presentation);
      case 'F': // Day of week
        return _formatDayOfWeek(dt.weekday, presentation);
      case 'W': // Week of year
        return _formatNumber(_weekOfYear(dt), presentation);
      case 'w': // Week of month
        return _formatNumber(_weekOfMonth(dt), presentation);
      case 'X': // ISO week-numbering year
        return _formatYear(_isoWeekYear(dt), presentation);
      case 'x': // Month containing the week
        return _formatMonthContainingWeek(dt, presentation);
      case 'H': // Hour (24-hour)
        return _formatNumber(dt.hour, presentation);
      case 'h': // Hour (12-hour)
        final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
        return _formatNumber(hour12, presentation);
      case 'P': // AM/PM marker
        return _formatAmPm(dt.hour, presentation);
      case 'm': // Minutes
        // Default to 2-digit zero-padded format
        return _formatNumber(dt.minute, presentation.isEmpty ? '01' : presentation);
      case 's': // Seconds
        // Default to 2-digit zero-padded format
        return _formatNumber(dt.second, presentation.isEmpty ? '01' : presentation);
      case 'f': // Fractional seconds
        return _formatFractionalSeconds(millis, presentation);
      case 'Z': // Timezone offset
        return _formatTimezone(tzOffsetMinutes, presentation, timezone);
      case 'z': // Timezone name
        return _formatTimezoneName(tzOffsetMinutes, presentation, timezone);
      case 'C': // Calendar
        return _formatCalendar(presentation);
      case 'E': // Era
        return _formatEra(presentation);
      default:
        return component;
    }
  }


  // Month and day names
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];

  /// Formats year with presentation modifiers.
  static String _formatYear(int year, String presentation) {
    // Check for 'N' or 'n' - names not supported for years
    if (presentation.contains('N') || presentation.contains('n')) {
      throw JsonataException('D3133',
          'Year component cannot be represented as a name',
          position: 0);
    }

    // For year, when width modifier is just `,N` (without `-`), treat it as max width
    // But only if there's no explicit pattern that specifies more digits
    final widthMatch = RegExp(r',(\d+)(?:-(\d+))?$').firstMatch(presentation);
    if (widthMatch != null && widthMatch.group(2) == null) {
      // Only min specified, treat it as max for year
      final width = int.parse(widthMatch.group(1)!);
      final basePresentation = presentation.substring(0, presentation.length - widthMatch.group(0)!.length);

      // Check if base presentation has an explicit pattern requiring more digits
      final patternDigits = basePresentation.replaceAll(RegExp(r'[^0-9#]'), '').length;
      if (patternDigits > width) {
        // Pattern requires more digits than width, use pattern
        return _formatNumber(year, presentation);
      }

      final yearStr = year.toString();
      if (yearStr.length > width && basePresentation.isEmpty) {
        // Take rightmost digits only when no pattern specified
        return yearStr.substring(yearStr.length - width);
      }
      return _formatNumber(year, basePresentation.isEmpty ? '1' : basePresentation);
    }

    return _formatNumber(year, presentation);
  }

  /// Formats month with presentation modifiers.
  static String _formatMonth(int month, String presentation) {
    // Check for name presentation
    if (presentation.startsWith('N') || presentation.startsWith('n')) {
      return _formatName(_monthNames[month - 1], presentation);
    }
    return _formatNumber(month, presentation);
  }

  /// Formats day of week with presentation modifiers.
  static String _formatDayOfWeek(int weekday, String presentation) {
    // If numeric format
    if (RegExp(r'^[0-9#]+$').hasMatch(presentation) ||
        presentation == '1') {
      // Sunday is 7 in Dart, but should be displayed as 7
      return _formatNumber(weekday, presentation);
    }
    // Default to lowercase name if no presentation
    if (presentation.isEmpty) {
      return _dayNames[weekday - 1].toLowerCase();
    }
    // Name presentation
    return _formatName(_dayNames[weekday - 1], presentation);
  }

  /// Formats AM/PM marker.
  static String _formatAmPm(int hour, String presentation) {
    final isAm = hour < 12;
    String marker;
    if (presentation.contains('N')) {
      marker = isAm ? 'AM' : 'PM';
    } else if (presentation.contains('n') || presentation.isEmpty) {
      // Default to lowercase
      marker = isAm ? 'am' : 'pm';
    } else {
      marker = isAm ? 'am' : 'pm';
    }
    return marker;
  }

  /// Formats fractional seconds.
  static String _formatFractionalSeconds(int millis, String presentation) {
    final ms = (millis % 1000).abs();
    // Count digits in pattern (0-9 and #)
    final digits = presentation.replaceAll(RegExp(r'[^0-9#]'), '').length;
    if (digits == 0) {
      return ms.toString().padLeft(3, '0');
    }
    final padded = ms.toString().padLeft(3, '0');
    return padded.substring(0, digits.clamp(1, 3));
  }

  /// Formats timezone offset.
  static String _formatTimezone(
      int tzOffsetMinutes, String presentation, dynamic timezone) {
    if (tzOffsetMinutes == 0 && presentation.contains('t')) {
      return 'Z';
    }

    final sign = tzOffsetMinutes >= 0 ? '+' : '-';
    final absMinutes = tzOffsetMinutes.abs();
    final hours = absMinutes ~/ 60;
    final minutes = absMinutes % 60;

    // Check for 6-digit format (error case) - must check first
    final digitCount = presentation.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digitCount >= 6) {
      throw JsonataException('D3134',
          'Timezone format is invalid: $presentation',
          position: 0);
    }

    // Check format pattern
    if (presentation.contains('01:01')) {
      // Full format with colon
      if (tzOffsetMinutes == 0 && presentation.contains('t')) {
        return 'Z';
      }
      return '$sign${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}';
    } else if (presentation.contains('0101')) {
      // Full format without colon
      return '$sign${hours.toString().padLeft(2, '0')}'
          '${minutes.toString().padLeft(2, '0')}';
    } else if (presentation.contains('0')) {
      // Short format
      if (minutes == 0) {
        return '$sign$hours';
      }
      return '$sign$hours:${minutes.toString().padLeft(2, '0')}';
    } else {
      // Default: +HH:MM
      return '$sign${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}';
    }
  }

  /// Formats timezone name.
  static String _formatTimezoneName(
      int tzOffsetMinutes, String presentation, dynamic timezone) {
    final sign = tzOffsetMinutes >= 0 ? '+' : '-';
    final absMinutes = tzOffsetMinutes.abs();
    final hours = absMinutes ~/ 60;
    final minutes = absMinutes % 60;
    return 'GMT$sign${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// Formats calendar name.
  static String _formatCalendar(String presentation) {
    return 'ISO';
  }

  /// Formats era name.
  static String _formatEra(String presentation) {
    return 'ISO';
  }

  /// Formats a name with presentation modifiers.
  static String _formatName(String name, String presentation) {
    // Parse width modifiers
    int? maxWidth;
    final widthMatch = RegExp(r',(\d+)(?:-(\d+))?$').firstMatch(presentation);
    if (widthMatch != null) {
      // First number is minWidth (not used for names), second is maxWidth
      maxWidth = widthMatch.group(2) != null
          ? int.parse(widthMatch.group(2)!)
          : null;
    }

    String result = name;

    // Apply case
    if (presentation.startsWith('N')) {
      if (presentation.length > 1 && presentation[1] == 'n') {
        // Title case - already correct
      } else {
        result = result.toUpperCase();
      }
    } else if (presentation.startsWith('n')) {
      result = result.toLowerCase();
    }

    // Apply width constraints
    if (maxWidth != null && result.length > maxWidth) {
      result = result.substring(0, maxWidth);
    }

    return result;
  }


  /// Formats a number with various presentation modifiers.
  static String _formatNumber(int value, String presentation) {
    // Parse width modifiers
    int? minWidth;
    int? maxWidth;
    final widthMatch = RegExp(r',(\d+)(?:-(\d+))?$').firstMatch(presentation);
    if (widthMatch != null) {
      minWidth = int.parse(widthMatch.group(1)!);
      maxWidth = widthMatch.group(2) != null
          ? int.parse(widthMatch.group(2)!)
          : null;
      // Remove width modifier from presentation for further processing
      presentation =
          presentation.substring(0, presentation.length - widthMatch.group(0)!.length);
    }

    // Handle different presentation types
    if (presentation.isEmpty || presentation == '1') {
      return _applyWidthConstraints(value.toString(), minWidth, maxWidth);
    }

    // Roman numerals
    if (presentation == 'I') {
      return _applyWidthConstraints(_toRomanNumeral(value), minWidth, maxWidth);
    }
    if (presentation == 'i') {
      return _applyWidthConstraints(
          _toRomanNumeral(value).toLowerCase(), minWidth, maxWidth);
    }

    // Words
    if (presentation == 'w') {
      return _applyWidthConstraints(_toWords(value), minWidth, maxWidth);
    }
    if (presentation == 'W') {
      return _applyWidthConstraints(_toWords(value).toUpperCase(), minWidth, maxWidth);
    }
    if (presentation == 'Ww') {
      final words = _toWords(value);
      return _applyWidthConstraints(
          words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1),
          minWidth, maxWidth);
    }

    // Ordinal words
    if (presentation == 'wo') {
      return _applyWidthConstraints(_toOrdinalWords(value), minWidth, maxWidth);
    }

    // Letter-based numbering (a=1, b=2, ..., z=26, aa=27, etc.)
    if (presentation == 'a') {
      return _applyWidthConstraints(_toLetterNumber(value, false), minWidth, maxWidth);
    }
    if (presentation == 'A') {
      return _applyWidthConstraints(_toLetterNumber(value, true), minWidth, maxWidth);
    }

    // Ordinal suffix (1st, 2nd, 3rd, etc.)
    if (presentation.endsWith('o')) {
      final basePattern = presentation.substring(0, presentation.length - 1);
      final formatted = _formatNumericPattern(value, basePattern);
      return _applyWidthConstraints(formatted + _ordinalSuffix(value), minWidth, maxWidth);
    }

    // Numeric patterns with padding
    if (presentation.contains('#') || RegExp(r'^[0-9]+$').hasMatch(presentation)) {
      return _applyWidthConstraints(_formatNumericPattern(value, presentation), minWidth, maxWidth);
    }

    // Check for grouping separator
    if (presentation.contains(',') && presentation.contains('*')) {
      return _formatWithGrouping(value, presentation);
    }

    return _applyWidthConstraints(value.toString(), minWidth, maxWidth);
  }

  /// Apply width constraints to a string.
  static String _applyWidthConstraints(String str, int? minWidth, int? maxWidth) {
    // Apply minimum width with zero padding for numeric strings
    if (minWidth != null && str.length < minWidth) {
      // Check if string is numeric (might have leading sign)
      if (RegExp(r'^-?\d+$').hasMatch(str)) {
        if (str.startsWith('-')) {
          str = '-${str.substring(1).padLeft(minWidth - 1, '0')}';
        } else {
          str = str.padLeft(minWidth, '0');
        }
      } else {
        // For non-numeric strings, pad with spaces
        str = str.padLeft(minWidth, ' ');
      }
    }
    // Apply maximum width (take rightmost characters)
    if (maxWidth != null && str.length > maxWidth) {
      str = str.substring(str.length - maxWidth);
    }
    return str;
  }

  /// Formats a number with a numeric pattern (e.g., "01", "001", "0001").
  static String _formatNumericPattern(int value, String pattern) {
    // Count all zeros and digits in pattern to determine width
    final digitCount = pattern.replaceAll(RegExp(r'[^0-9]'), '').length;
    final zeroCount = pattern.replaceAll(RegExp(r'[^0]'), '').length;

    // If pattern has zeros, pad to the total digit count
    if (zeroCount > 0 && digitCount > 0) {
      return value.toString().padLeft(digitCount, '0');
    }

    // Count # symbols (optional digits)
    final hashCount = pattern.replaceAll(RegExp(r'[^#]'), '').length;
    if (hashCount > 0) {
      return value.toString();
    }

    return value.toString();
  }

  /// Formats a number with grouping separators.
  static String _formatWithGrouping(int value, String presentation) {
    final str = value.toString();
    final result = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        result.write(',');
      }
      result.write(str[i]);
    }
    return result.toString();
  }

  /// Returns ordinal suffix for a number.
  static String _ordinalSuffix(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  /// Converts number to Roman numerals.
  static String _toRomanNumeral(int num) {
    if (num <= 0) return num.toString();
    final romanNumerals = [
      ['M', 1000], ['CM', 900], ['D', 500], ['CD', 400],
      ['C', 100], ['XC', 90], ['L', 50], ['XL', 40],
      ['X', 10], ['IX', 9], ['V', 5], ['IV', 4], ['I', 1]
    ];
    final result = StringBuffer();
    var remaining = num;
    for (final pair in romanNumerals) {
      final symbol = pair[0] as String;
      final value = pair[1] as int;
      while (remaining >= value) {
        result.write(symbol);
        remaining -= value;
      }
    }
    return result.toString();
  }

  /// Converts number to letter-based numbering (a=1, b=2, ...).
  static String _toLetterNumber(int num, bool uppercase) {
    if (num <= 0) return '';
    final result = StringBuffer();
    var remaining = num;
    while (remaining > 0) {
      remaining--;
      final letter = String.fromCharCode((remaining % 26) + (uppercase ? 65 : 97));
      result.write(letter);
      remaining ~/= 26;
    }
    return result.toString().split('').reversed.join();
  }


  /// Converts a number to words.
  static String _toWords(int num) {
    if (num == 0) return 'zero';
    if (num < 0) return 'minus ${_toWords(-num)}';

    const ones = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
        'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
        'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
    const tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty',
        'seventy', 'eighty', 'ninety'];

    String helper(int n) {
      if (n < 20) return ones[n];
      if (n < 100) {
        final remainder = n % 10;
        return tens[n ~/ 10] + (remainder > 0 ? '-${ones[remainder]}' : '');
      }
      if (n < 1000) {
        final remainder = n % 100;
        return '${ones[n ~/ 100]} hundred${remainder > 0 ? ' and ${helper(remainder)}' : ''}';
      }
      if (n < 1000000) {
        final remainder = n % 1000;
        return '${helper(n ~/ 1000)} thousand${remainder > 0 ? '${remainder < 100 ? ' and ' : ', '}${helper(remainder)}' : ''}';
      }
      if (n < 1000000000) {
        final remainder = n % 1000000;
        return '${helper(n ~/ 1000000)} million${remainder > 0 ? '${remainder < 100 ? ' and ' : ', '}${helper(remainder)}' : ''}';
      }
      final remainder = n % 1000000000;
      return '${helper(n ~/ 1000000000)} billion${remainder > 0 ? '${remainder < 100 ? ' and ' : ', '}${helper(remainder)}' : ''}';
    }

    return helper(num);
  }

  /// Converts a number to ordinal words.
  static String _toOrdinalWords(int num) {
    if (num == 0) return 'zeroth';
    if (num < 0) return 'minus ${_toOrdinalWords(-num)}';

    const ordinalOnes = ['', 'first', 'second', 'third', 'fourth', 'fifth',
        'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth',
        'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth', 'seventeenth',
        'eighteenth', 'nineteenth'];
    const ordinalTens = ['', '', 'twentieth', 'thirtieth', 'fortieth',
        'fiftieth', 'sixtieth', 'seventieth', 'eightieth', 'ninetieth'];
    const tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty',
        'seventy', 'eighty', 'ninety'];

    if (num < 20) return ordinalOnes[num];
    if (num < 100) {
      final remainder = num % 10;
      if (remainder == 0) return ordinalTens[num ~/ 10];
      return '${tens[num ~/ 10]}-${ordinalOnes[remainder]}';
    }

    // For larger numbers, convert to words and add suffix
    final words = _toWords(num);
    // Handle special ending cases
    if (words.endsWith('one')) return '${words.substring(0, words.length - 3)}first';
    if (words.endsWith('two')) return '${words.substring(0, words.length - 3)}second';
    if (words.endsWith('three')) return '${words.substring(0, words.length - 5)}third';
    if (words.endsWith('five')) return '${words.substring(0, words.length - 4)}fifth';
    if (words.endsWith('eight')) return '${words}h';
    if (words.endsWith('nine')) return '${words.substring(0, words.length - 4)}ninth';
    if (words.endsWith('twelve')) return '${words.substring(0, words.length - 6)}twelfth';
    if (words.endsWith('y')) return '${words.substring(0, words.length - 1)}ieth';
    return '${words}th';
  }

  /// Calculates day of year (1-366).
  static int _dayOfYear(DateTime dt) {
    final firstDay = DateTime.utc(dt.year, 1, 1);
    return dt.difference(firstDay).inDays + 1;
  }

  /// Calculates ISO week of year (1-53).
  static int _weekOfYear(DateTime dt) {
    // ISO week date: Week 1 is the week containing the first Thursday
    final jan4 = DateTime.utc(dt.year, 1, 4);
    final weekday = jan4.weekday; // 1=Monday, 7=Sunday
    final firstMonday = jan4.subtract(Duration(days: weekday - 1));
    final diff = dt.difference(firstMonday).inDays;
    if (diff < 0) {
      // Date is in the last week of previous year
      return _weekOfYear(DateTime.utc(dt.year - 1, 12, 31));
    }
    final week = (diff ~/ 7) + 1;
    if (week > 52) {
      // Check if this week belongs to next year
      final nextYearJan4 = DateTime.utc(dt.year + 1, 1, 4);
      final nextWeekday = nextYearJan4.weekday;
      final nextFirstMonday = nextYearJan4.subtract(Duration(days: nextWeekday - 1));
      if (!dt.isBefore(nextFirstMonday)) {
        return 1;
      }
    }
    return week;
  }

  /// Calculates ISO week-numbering year.
  static int _isoWeekYear(DateTime dt) {
    // The ISO week-numbering year may differ from the calendar year
    final week = _weekOfYear(dt);
    if (week == 1 && dt.month == 12) {
      return dt.year + 1;
    }
    if (week >= 52 && dt.month == 1) {
      return dt.year - 1;
    }
    return dt.year;
  }

  /// Calculates week of month based on the ISO week rule applied to months:
  /// The week belongs to the month containing the Thursday of that week.
  /// Returns both the week number and the month containing the Thursday.
  static (int week, int month, int year) _weekOfMonthInfo(DateTime dt) {
    // Find the Monday of the week containing dt
    final daysFromMonday = (dt.weekday - 1);  // Monday = 1, so Monday = 0 days back
    final monday = dt.subtract(Duration(days: daysFromMonday));

    // Find Thursday of the same week (Thursday determines which month the week belongs to)
    final thursday = monday.add(const Duration(days: 3));

    // The week belongs to the month containing Thursday
    final weekMonth = thursday.month;
    final weekYear = thursday.year;

    // Calculate which week of that month this is
    // Find the first Thursday of that month
    final firstOfWeekMonth = DateTime.utc(weekYear, weekMonth, 1);
    DateTime firstThursday;
    if (firstOfWeekMonth.weekday <= 4) {
      // Thursday is on or after the 1st
      firstThursday = firstOfWeekMonth.add(Duration(days: 4 - firstOfWeekMonth.weekday));
    } else {
      // Thursday is in the next week
      firstThursday = firstOfWeekMonth.add(Duration(days: 11 - firstOfWeekMonth.weekday));
    }

    // Week number is 1 + number of weeks between first Thursday and this Thursday
    final weekNum = ((thursday.difference(firstThursday).inDays) ~/ 7) + 1;
    return (weekNum, weekMonth, weekYear);
  }

  /// Calculates week of month.
  static int _weekOfMonth(DateTime dt) {
    return _weekOfMonthInfo(dt).$1;
  }

  /// Gets the month containing the week for a given date.
  static String _formatMonthContainingWeek(DateTime dt, String presentation) {
    final info = _weekOfMonthInfo(dt);
    final month = info.$2;

    // Check for name presentation
    if (presentation.startsWith('N') || presentation.startsWith('n')) {
      return _formatName(_monthNames[month - 1], presentation);
    }
    return _formatNumber(month, presentation);
  }

  /// Parses a timestamp string using XPath/XQuery picture string.
  /// Uses regex-based approach similar to the JavaScript implementation.
  static dynamic _parseWithPicture(String timestamp, String picture) {
    // Parse the picture string to extract parts (literals and markers)
    final parts = <_PicturePart>[];
    var i = 0;
    var currentLiteral = StringBuffer();

    while (i < picture.length) {
      final char = picture[i];

      if (char == '[') {
        if (i + 1 < picture.length && picture[i + 1] == '[') {
          currentLiteral.write('[');
          i += 2;
          continue;
        }
        if (currentLiteral.isNotEmpty) {
          parts.add(_PicturePart.literal(currentLiteral.toString()));
          currentLiteral = StringBuffer();
        }
        final closeBracket = picture.indexOf(']', i);
        if (closeBracket < 0) {
          throw JsonataException('D3135',
              'Picture string contains unclosed bracket',
              position: 0);
        }
        final component = picture.substring(i + 1, closeBracket);
        final cleanComponent = component.replaceAll(RegExp(r'\s'), '');
        if (cleanComponent.isNotEmpty) {
          final specifier = cleanComponent[0];
          final presentation = cleanComponent.length > 1 ? cleanComponent.substring(1) : '';

          // D3132: Validate the component specifier is known
          const validSpecifiers = 'YMDdFWwXxHhPmsfZzCE';
          if (!validSpecifiers.contains(specifier)) {
            throw JsonataException('D3132',
                'Unknown component specifier \'$specifier\' in date/time picture string',
                position: 0, value: specifier);
          }

          // D3133: Validate name presentation is only used with supported components
          // Name presentations start with 'N' or 'n' (e.g., 'N', 'Nn', 'n')
          final firstPres = presentation.isNotEmpty ? presentation[0] : '';
          final isNamePresentation = firstPres == 'N' || firstPres == 'n';
          if (isNamePresentation) {
            // Only M, x, F, P support name presentation
            const nameableSpecifiers = 'MxFP';
            if (!nameableSpecifiers.contains(specifier)) {
              throw JsonataException('D3133',
                  'Component specifier \'$specifier\' does not support name format',
                  position: 0, value: specifier);
            }
          }

          parts.add(_PicturePart.marker(_PictureComponent(specifier, presentation)));
        }
        i = closeBracket + 1;
      } else if (char == ']') {
        if (i + 1 < picture.length && picture[i + 1] == ']') {
          currentLiteral.write(']');
          i += 2;
          continue;
        }
        currentLiteral.write(char);
        i++;
      } else {
        currentLiteral.write(char);
        i++;
      }
    }

    // Add trailing literal
    if (currentLiteral.isNotEmpty) {
      parts.add(_PicturePart.literal(currentLiteral.toString()));
    }

    // If only literals in picture, return undefined
    if (!parts.any((p) => p.isMarker)) {
      return undefined;
    }

    // Build regex from parts
    // For consecutive integer components, use fixed widths
    final regexParts = <String>[];
    final markerIndices = <int>[]; // indices of capturing groups that are markers

    for (var partIdx = 0; partIdx < parts.length; partIdx++) {
      final part = parts[partIdx];
      if (part.isLiteral) {
        // Escape special regex characters in literals
        regexParts.add('(${_escapeRegex(part.literal!)})');
      } else {
        // Check if next part is also a numeric marker (no literal between them)
        bool nextIsNumericMarker = false;
        if (partIdx + 1 < parts.length) {
          final nextPart = parts[partIdx + 1];
          if (nextPart.isMarker && _isNumericComponent(nextPart.component!)) {
            nextIsNumericMarker = true;
          }
        }

        // Generate regex for this marker
        // If this and next are consecutive numeric components, use fixed width
        final regex = _generateComponentRegex(part.component!,
            fixedWidth: nextIsNumericMarker && _isNumericComponent(part.component!));
        regexParts.add('($regex)');
        markerIndices.add(partIdx);
      }
    }

    final fullRegex = '^${regexParts.join('')}\$';
    final matcher = RegExp(fullRegex, caseSensitive: false);
    final match = matcher.firstMatch(timestamp);

    if (match == null) {
      return undefined;
    }

    // Extract values from match groups
    // Track which specific components were specified using a map
    final components = <String, int>{};

    final now = DateTime.now();
    int year = now.year;
    int month = 1;
    int day = 1;
    int dayOfYear = 0;
    int hour = 0;
    int minute = 0;
    int second = 0;
    int millisecond = 0;
    int tzOffsetMinutes = 0;
    bool isPM = false;
    bool is12Hour = false;

    for (var groupIdx = 1; groupIdx <= parts.length; groupIdx++) {
      final part = parts[groupIdx - 1];
      if (!part.isMarker) continue;

      final value = match.group(groupIdx);
      if (value == null) continue;

      final parsedValue = _parseMatchedValue(value, part.component!);
      if (parsedValue == null) continue;

      // Track the component as specified
      components[part.component!.specifier] = parsedValue;

      switch (part.component!.specifier) {
        case 'Y':
        case 'X':
          year = parsedValue;
          break;
        case 'M':
        case 'x':
          month = parsedValue;
          break;
        case 'D':
        case 'F':
          day = parsedValue;
          break;
        case 'd':
          dayOfYear = parsedValue;
          break;
        case 'W':
        case 'w':
          // Week components - tracked in components map
          break;
        case 'H':
          hour = parsedValue;
          break;
        case 'h':
          hour = parsedValue;
          is12Hour = true;
          break;
        case 'm':
          minute = parsedValue;
          break;
        case 's':
          second = parsedValue;
          break;
        case 'f':
          millisecond = parsedValue;
          break;
        case 'Z':
        case 'z':
          tzOffsetMinutes = parsedValue;
          break;
        case 'P':
          isPM = parsedValue == 1;
          is12Hour = true;
          break;
      }
    }

    // If no components specified, return undefined
    if (components.isEmpty) {
      return undefined;
    }

    // D3136: Check for unsupported ISO week date formats (dateC and dateD)
    // dateC: {X, x, w, F} - year/month-of-year/week-of-month/day-of-week
    // dateD: {X, W, F} - year/week-of-year/day-of-week
    final hasX = components.containsKey('X');
    final hasW = components.containsKey('W');
    final hasw = components.containsKey('w');
    final hasx = components.containsKey('x');
    final hasF = components.containsKey('F');

    // Check for dateC format: X, x, w, F
    final isDateC = hasX && hasx && hasw && hasF;
    // Check for dateD format: X, W, F
    final isDateD = hasX && hasW && hasF;

    if (isDateC || isDateD) {
      throw JsonataException('D3136',
          'ISO week date format is not currently supported for parsing',
          position: 0);
    }

    // D3136: Check for gaps in date/time components
    // Date formats: {Y, M, D} or {Y, d}
    // Time formats: {H, m, s, f} or {P, h, m, s, f}
    // There should be no gaps in the specified components

    // Determine which date format we're using
    final hasY = components.containsKey('Y');
    final hasM = components.containsKey('M');
    final hasD = components.containsKey('D');
    final hasd = components.containsKey('d');

    // Determine which time format we're using
    final hasH = components.containsKey('H');
    final hash = components.containsKey('h');
    final hasm = components.containsKey('m');
    final hass = components.containsKey('s');
    final hasf = components.containsKey('f');
    final hasP = components.containsKey('P');

    // Check for date gaps: if we have Y and D but no M, that's a gap (unless using day-of-year 'd')
    if (hasY && hasD && !hasM && !hasd) {
      throw JsonataException('D3136',
          'Date/time is underspecified - year and day specified but no month',
          position: 0);
    }

    // Check for time gaps: if we have m or s but no H or h, that's a gap
    if ((hasm || hass || hasf) && !hasH && !hash) {
      throw JsonataException('D3136',
          'Date/time is underspecified - time components specified but no hour',
          position: 0);
    }

    // Check for time gaps: if we have s or f but no m
    if ((hass || hasf) && !hasm) {
      throw JsonataException('D3136',
          'Date/time is underspecified - seconds/fractional seconds specified but no minutes',
          position: 0);
    }

    // Handle 12-hour clock with AM/PM
    if (is12Hour) {
      if (hour == 12) {
        hour = isPM ? 12 : 0;
      } else if (isPM) {
        hour += 12;
      }
    }

    // Determine if only time was specified (no date components)
    final hasTimeOnly = (hasH || hash || hasm || hass || hasf || hasP) &&
        !hasY && !hasM && !hasD && !hasd && !hasX && !hasW && !hasw && !hasx && !hasF;

    // Default unspecified date parts to today if only time was specified
    if (hasTimeOnly) {
      month = now.month;
      day = now.day;
    }

    // Handle day of year
    if (dayOfYear > 0) {
      final jan1 = DateTime.utc(year, 1, 1);
      final targetDate = jan1.add(Duration(days: dayOfYear - 1));
      month = targetDate.month;
      day = targetDate.day;
    }

    final dt = DateTime.utc(year, month, day, hour, minute, second, millisecond);
    // Apply timezone offset (convert from local to UTC)
    return dt.millisecondsSinceEpoch - tzOffsetMinutes * 60 * 1000;
  }

  /// Escape special regex characters.
  static String _escapeRegex(String text) {
    return text.replaceAllMapped(
      RegExp(r'[.*+?^${}()|[\]\\]'),
      (m) => '\\${m.group(0)}',
    );
  }

  /// Check if a component is numeric (decimal digits).
  static bool _isNumericComponent(_PictureComponent comp) {
    final presentation = comp.presentation.toLowerCase();
    // Numeric if it's digits (not name, word, roman, or letter-based)
    if (presentation.startsWith('n')) return false;  // Name presentation
    if (presentation.startsWith('w')) return false;  // Word presentation
    if (presentation == 'i') return false;  // Roman numerals
    if (presentation == 'a') return false;  // Letter-based
    if (comp.specifier == 'P') return false;  // AM/PM
    // Default is numeric for Y, M, D, d, H, h, m, s, f
    return 'YMDdHhmsf'.contains(comp.specifier);
  }

  /// Get the mandatory digit count from presentation string.
  static int _getMandatoryDigits(String presentation) {
    // Handle formats like "*-4" or ",*-4" which specify width after the dash
    final widthMatch = RegExp(r'-(\d+)$').firstMatch(presentation);
    if (widthMatch != null) {
      return int.parse(widthMatch.group(1)!);
    }

    // Count the number of zeros and digits in the presentation
    // e.g., "0001" has 4 mandatory digits, "01" has 2
    int count = 0;
    for (var c in presentation.split('')) {
      if (c == '0' || RegExp(r'[1-9]').hasMatch(c)) count++;
    }
    return count > 0 ? count : 1;
  }

  /// Generate regex pattern for a picture component.
  static String _generateComponentRegex(_PictureComponent comp, {bool fixedWidth = false}) {
    final specifier = comp.specifier;
    final presentation = comp.presentation;

    // Timezone
    if (specifier == 'Z') {
      return r'[-+][0-9]+(?::[0-9]+)?';
    }
    if (specifier == 'z') {
      return r'GMT[-+][0-9]+(?::[0-9]+)?';
    }

    // AM/PM
    if (specifier == 'P') {
      return r'[AaPp][Mm]?';
    }

    // Name presentation (months, days)
    if (presentation.startsWith('N') || presentation.startsWith('n')) {
      return r'[a-zA-Z]+';
    }

    // Word presentation (w, W, wo, Ww, Wwo, wWo, etc.)
    if (presentation.toLowerCase().startsWith('w')) {
      // Match word-based numbers using only known number words
      // This prevents matching non-number words like month names
      return _numberWordsRegex;
    }

    // Roman numerals
    if (presentation == 'I' || presentation == 'i') {
      return r'[IVXLCDMivxlcdm]+';
    }

    // Letter-based (a, b, c...)
    if (presentation == 'a' || presentation == 'A') {
      return r'[a-zA-Z]+';
    }

    // Ordinal numbers
    if (presentation.endsWith('o')) {
      return r'[0-9]+(?:st|nd|rd|th)';
    }

    // Default: decimal numbers
    if (fixedWidth) {
      // Use fixed width based on mandatory digits
      final width = _getMandatoryDigits(presentation);
      return '[0-9]{$width}';
    }
    return r'[0-9]+';
  }

  /// Parse a matched string value according to the component specification.
  static int? _parseMatchedValue(String value, _PictureComponent comp) {
    final specifier = comp.specifier;
    final presentation = comp.presentation;

    // Timezone
    if (specifier == 'Z' || specifier == 'z') {
      var v = value;
      if (specifier == 'z' && v.startsWith('GMT')) {
        v = v.substring(3);
      }
      return _parseTimezoneValue(v);
    }

    // AM/PM
    if (specifier == 'P') {
      return value.toLowerCase().startsWith('p') ? 1 : 0;
    }

    // Month/Day names
    if ((specifier == 'M' || specifier == 'F') &&
        (presentation.startsWith('N') || presentation.startsWith('n'))) {
      if (specifier == 'M') {
        return _parseMonthName(value);
      } else {
        return _parseDayName(value);
      }
    }

    // Word presentation
    // Word presentation (w, W, wo, Ww, Wwo, etc.)
    if (presentation.toLowerCase().startsWith('w')) {
      return _fromWords(value);
    }

    // Roman numerals
    if (presentation == 'I' || presentation == 'i') {
      return _fromRomanNumeral(value.toUpperCase());
    }

    // Letter-based
    if (presentation == 'a' || presentation == 'A') {
      return _fromLetters(value);
    }

    // Ordinal - strip suffix
    if (presentation.endsWith('o')) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(digits);
    }

    // Default: parse as integer
    return int.tryParse(value);
  }

  /// Parse timezone offset string.
  static int _parseTimezoneValue(String value) {
    final sign = value.startsWith('-') ? -1 : 1;
    final v = value.substring(1); // remove sign

    if (v.contains(':')) {
      final parts = v.split(':');
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      return sign * (hours * 60 + minutes);
    } else {
      final num = int.tryParse(v) ?? 0;
      if (num > 99) {
        // Format like +0530
        return sign * ((num ~/ 100) * 60 + (num % 100));
      } else {
        // Just hours
        return sign * num * 60;
      }
    }
  }

  /// Parse month name to month number (1-12).
  static int _parseMonthName(String name) {
    final lower = name.toLowerCase();
    for (var i = 0; i < _monthNames.length; i++) {
      if (_monthNames[i].toLowerCase().startsWith(lower) ||
          lower.startsWith(_monthNames[i].substring(0, 3).toLowerCase())) {
        return i + 1;
      }
    }
    return 1;
  }

  /// Parse day name to day number (1-7).
  static int _parseDayName(String name) {
    final lower = name.toLowerCase();
    for (var i = 0; i < _dayNames.length; i++) {
      if (_dayNames[i].toLowerCase().startsWith(lower) ||
          lower.startsWith(_dayNames[i].substring(0, 3).toLowerCase())) {
        return i + 1;
      }
    }
    return 1;
  }

  /// Convert letters to number (a=1, b=2, ..., z=26, aa=27, ...).
  static int _fromLetters(String letters) {
    final lower = letters.toLowerCase();
    var result = 0;
    for (var i = 0; i < lower.length; i++) {
      result = result * 26 + (lower.codeUnitAt(i) - 'a'.codeUnitAt(0) + 1);
    }
    return result;
  }

  /// Convert Roman numeral string to integer.
  static int _fromRomanNumeral(String roman) {
    final values = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};
    var result = 0;
    var prev = 0;
    for (var i = roman.length - 1; i >= 0; i--) {
      final value = values[roman[i]] ?? 0;
      if (value < prev) {
        result -= value;
      } else {
        result += value;
      }
      prev = value;
    }
    return result;
  }


  /// Convert words to a number.
  static int _fromWords(String words) {
    final normalized = words.toLowerCase().trim();

    // Handle common word numbers
    final ones = {
      'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
      'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
      'nineteen': 19, 'first': 1, 'second': 2, 'third': 3, 'fourth': 4,
      'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9,
      'tenth': 10, 'eleventh': 11, 'twelfth': 12
    };

    // Ordinal forms that end with -th (e.g., twenty-first, thirty-second)
    final ordinalOnes = {
      'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
      'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9
    };

    final tens = {
      'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
      'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
      'twentieth': 20, 'thirtieth': 30, 'fortieth': 40, 'fiftieth': 50,
      'sixtieth': 60, 'seventieth': 70, 'eightieth': 80, 'ninetieth': 90
    };

    final multipliers = {
      'hundred': 100, 'thousand': 1000, 'million': 1000000, 'billion': 1000000000
    };

    // Simple single word lookup
    if (ones.containsKey(normalized)) return ones[normalized]!;
    if (tens.containsKey(normalized)) return tens[normalized]!;

    // Handle hyphenated ordinals like "twenty-first", "thirty-second"
    if (normalized.contains('-')) {
      final parts = normalized.split('-');
      if (parts.length == 2) {
        final tensVal = tens[parts[0]];
        final onesVal = ones[parts[1]] ?? ordinalOnes[parts[1]];
        if (tensVal != null && onesVal != null) {
          return tensVal + onesVal;
        }
      }
    }

    // Parse complex number words (e.g., "one thousand, nine hundred and eighty-four")
    // First replace hyphens with spaces and normalize
    final cleanWords = normalized.replaceAll('-', ' ');
    final parts = cleanWords.split(RegExp(r'[\s,]+'));
    var result = 0;
    var current = 0;

    for (final part in parts) {
      final word = part.trim();
      if (word.isEmpty || word == 'and') continue;

      if (ones.containsKey(word)) {
        current += ones[word]!;
      } else if (tens.containsKey(word)) {
        current += tens[word]!;
      } else if (multipliers.containsKey(word)) {
        if (current == 0) current = 1;
        final mult = multipliers[word]!;
        if (mult >= 1000) {
          result += current * mult;
          current = 0;
        } else {
          current *= mult;
        }
      }
    }

    return result + current;
  }

}

/// Helper class to hold picture component information.
class _PictureComponent {
  final String specifier;
  final String presentation;

  _PictureComponent(this.specifier, this.presentation);
}

/// Helper class to hold a picture part (literal or marker).
class _PicturePart {
  final bool isLiteral;
  final String? literal;
  final _PictureComponent? component;

  _PicturePart.literal(this.literal)
      : isLiteral = true,
        component = null;

  _PicturePart.marker(this.component)
      : isLiteral = false,
        literal = null;

  bool get isMarker => !isLiteral;
}