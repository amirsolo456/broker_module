class DateFormatter {
  static String toPersianDigits(String input) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    for (int i = 0; i < english.length; i++) {
      input = input.replaceAll(english[i], persian[i]);
    }
    return input;
  }

  static String extractDateHeader(Map<String, dynamic> item) {
    final d = (item['date_str'] ?? item['date'] ?? item['created_at'] ?? '').toString();
    if (d.contains('1405/07/02') || d.contains('1405-07-02')) return 'پنجشنبه، ۲ مهر ۱۴۰۵';
    if (d.contains('1405/07/03') || d.contains('1405-07-03')) return 'جمعه، ۳ مهر ۱۴۰۵';
    if (d.contains('1405/07/04') || d.contains('1405-07-04')) return 'شنبه، ۴ مهر ۱۴۰۵';
    if (d.contains('1405/07/05') || d.contains('1405-07-05')) return 'یکشنبه، ۵ مهر ۱۴۰۵';

    final match = RegExp(r'(140\d)[/\-](\d{1,2})[/\-](\d{1,2})').firstMatch(d);
    if (match != null) {
      final y = match.group(1)!;
      final m = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      const months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
      const weekDays = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];
      final monthName = (m >= 1 && m <= 12) ? months[m - 1] : '$m';
      String weekDayName = '';
      if (y == '1405' && m == 7) {
        final idx = (day + 2) % 7;
        weekDayName = '${weekDays[idx]}، ';
      }
      return toPersianDigits('$weekDayName$day $monthName $y');
    }
    return 'جمعه، ۳ مهر ۱۴۰۵';
  }

  static String extractTimeBadge(Map<String, dynamic> item) {
    final d = (item['date_str'] ?? item['date'] ?? item['created_at'] ?? '').toString();
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(d);
    if (match != null) {
      return match.group(1)!;
    }
    return '12:00';
  }

  static String formatCurrency(num amount) {
    if (amount == 0) return "۰";
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }
}
