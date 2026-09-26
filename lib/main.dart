import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'core/constants/app_constants.dart';
import 'core/utils/date_formatter.dart';
import 'presentation/widgets/summary_header_widget.dart';
import 'presentation/widgets/filter_search_card.dart';
import 'presentation/widgets/rubika_chat_bubble.dart';

void main() {
  runApp(const RubikaDiscountApp());
}

class RubikaDiscountApp extends StatelessWidget {
  const RubikaDiscountApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ماژول تخفیف و مدیریت روبیکا',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF673AB7),
          brightness: Brightness.light,
        ),
        fontFamily: 'IRANSans',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: ReceiptsHomePage(),
      ),
    );
  }
}

class ReceiptsHomePage extends StatefulWidget {
  const ReceiptsHomePage({super.key});

  @override
  State<ReceiptsHomePage> createState() => _ReceiptsHomePageState();
}

class _ReceiptsHomePageState extends State<ReceiptsHomePage> {
  late String baseServerUrl;

  String get serverUrl => "$baseServerUrl/api/receipts";
  String get rulesUrl => "$baseServerUrl/api/auto-responses";
  String get smmBalanceUrl => "$baseServerUrl/api/smm/balance";
  String get smmServicesUrl => "$baseServerUrl/api/smm/services";
  String get smmOrderUrl => "$baseServerUrl/api/smm/order";

  List<dynamic> receipts = [];
  List<dynamic> autoRules = [];
  List<dynamic> smmServices = [];
  Map<String, dynamic>? smmBalanceData;

  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMoreOlder = true;
  String errorMessage = "";
  String searchQuery = "";
  bool onlyCompletedFilter = false;
  int _selectedIndex = 0;

  late final ScrollController _scrollController;
  Timer? autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    baseServerUrl = AppConstants.defaultBaseHost;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadSavedServerUrl();
    autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => fetchAllData(isSilent: true));
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 100 && !isLoadingMore && hasMoreOlder && receipts.isNotEmpty) {
      fetchOlderReceipts();
    }
  }

  Future<void> fetchOlderReceipts() async {
    if (isLoadingMore || receipts.isEmpty) return;
    setState(() {
      isLoadingMore = true;
    });

    try {
      final minId = receipts.map((r) => r['id'] as int? ?? 0).reduce((a, b) => a < b ? a : b);
      final url = Uri.parse('$serverUrl?limit=20&before_id=$minId');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true && body['data'] is List) {
          final List olderData = body['data'];
          if (olderData.isEmpty) {
            setState(() {
              hasMoreOlder = false;
              isLoadingMore = false;
            });
          } else {
            setState(() {
              final existingIds = receipts.map((r) => r['id']).toSet();
              for (var item in olderData) {
                if (!existingIds.contains(item['id'])) {
                  receipts.add(item);
                }
              }
              isLoadingMore = false;
            });
          }
        }
      }
    } catch (_) {
      setState(() {
        isLoadingMore = false;
      });
    }
  }

  Future<void> _loadSavedServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('base_server_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        setState(() {
          baseServerUrl = savedUrl.trim();
        });
      }
    } catch (_) {}
    fetchAllData();
  }

  Future<void> _saveServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('base_server_url', url);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchAllData({bool isSilent = false}) async {
    await fetchReceipts(isSilent: isSilent);
    await fetchAutoRules(isSilent: isSilent);
    await fetchSmmBalance();
    await fetchSmmServices();
  }

  Future<void> fetchReceipts({bool isSilent = false}) async {
    if (!isSilent && receipts.isEmpty) {
      setState(() {
        isLoading = true;
        errorMessage = "";
      });
    }

    try {
      final response = await http.get(Uri.parse(serverUrl)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true && body['data'] is List) {
          final List newData = body['data'];
          setState(() {
            if (receipts.isEmpty || !isSilent) {
              final existingMap = {for (var r in receipts) r['id']: r};
              for (var item in newData) {
                existingMap[item['id']] = item;
              }
              receipts = existingMap.values.toList();
            } else {
              final existingIds = receipts.map((r) => r['id']).toSet();
              for (var item in newData) {
                if (!existingIds.contains(item['id'])) {
                  receipts.insert(0, item);
                } else {
                  final idx = receipts.indexWhere((r) => r['id'] == item['id']);
                  if (idx != -1) {
                    receipts[idx] = item;
                  }
                }
              }
            }
            isLoading = false;
            errorMessage = "";
          });
        }
      } else {
        if (!isSilent && receipts.isEmpty) {
          setState(() {
            errorMessage = "خطا در دریافت اطلاعات صورتحساب‌ها (${response.statusCode})";
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!isSilent && receipts.isEmpty) {
        setState(() {
          errorMessage = "امکان اتصال به سرور ($baseServerUrl) نیست.\nلطفاً بررسی کنید server.py روی ویندوز در حال اجرا باشد.\n\nخطا: $e";
          isLoading = false;
        });
      }
    }
  }

  Future<void> fetchAutoRules({bool isSilent = false}) async {
    try {
      final response = await http.get(Uri.parse(rulesUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true) {
          setState(() {
            autoRules = body['data'] ?? [];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> fetchSmmBalance() async {
    try {
      final response = await http.get(Uri.parse(smmBalanceUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true) {
          setState(() {
            smmBalanceData = body['data'];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> fetchSmmServices() async {
    try {
      final response = await http.get(Uri.parse(smmServicesUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true && body['data'] is List) {
          setState(() {
            smmServices = body['data'];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> addAutoRule(String keyword, String responseText) async {
    try {
      final response = await http.post(
        Uri.parse(rulesUrl),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({
          "keyword": keyword,
          "response_text": responseText,
          "match_type": "contains"
        }),
      );
      if (response.statusCode == 200) {
        fetchAutoRules();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('قانون جدید ثبت شد')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ثبت: $e')),
        );
      }
    }
  }

  Future<void> deleteAutoRule(int id) async {
    try {
      final response = await http.delete(Uri.parse('$rulesUrl/$id'));
      if (response.statusCode == 200) {
        fetchAutoRules();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('قانون حذف شد')),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> submitSmmOrder(String serviceId, String link, int quantity) async {
    try {
      final response = await http.post(
        Uri.parse(smmOrderUrl),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({
          "service": serviceId,
          "link": link,
          "quantity": quantity
        }),
      );
      final resJson = json.decode(utf8.decode(response.bodyBytes));

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('نتیجه ثبت سفارش rubika1.ir'),
            content: SelectableText(const JsonEncoder.withIndent('  ').convert(resJson)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))
            ],
          ),
        );
      }
      fetchSmmBalance();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    }
  }

  List<dynamic> get filteredReceipts {
    return receipts.where((item) {
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final raw = (item['raw_text'] ?? '').toString().toLowerCase();
        final tracking = (item['tracking_number'] ?? '').toString().toLowerCase();
        final bank = (item['bank_name'] ?? '').toString().toLowerCase();
        final sender = (item['sender'] ?? '').toString().toLowerCase();
        final phones = (item['phones'] ?? '').toString().toLowerCase();

        return raw.contains(q) || tracking.contains(q) || bank.contains(q) || sender.contains(q) || phones.contains(q);
      }

      return true;
    }).toList();
  }

  num get totalAmount {
    num sum = 0;
    for (var item in receipts) {
      if (item['category'] == 'bank_receipt') {
        sum += (item['amount'] ?? 0);
      }
    }
    return sum;
  }

  num get totalDiscounts {
    num sum = 0;
    for (var item in receipts) {
      sum += (item['discount_amount'] ?? 0);
    }
    return sum;
  }

  String formatCurrency(num amount) {
    if (amount == 0) return "۰";
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0 ? 'داشبورد و پایش صورتحساب‌ها' : 'پاسخگوی هوشمند روبیکا',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'بروزرسانی',
            onPressed: () => fetchAllData(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'تنظیمات آدرس سرور',
            onPressed: showServerUrlDialog,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildCompletedOrdersTab(theme),
          _buildAutoRulesTab(theme),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: const Color(0xFF673AB7),
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'IRANSans'),
        unselectedLabelStyle: const TextStyle(fontFamily: 'IRANSans'),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: 'داشبورد (${receipts.length})',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.smart_toy_outlined),
            activeIcon: const Icon(Icons.smart_toy),
            label: 'پاسخگوی هوشمند (${autoRules.length})',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton.extended(
              onPressed: showAddRuleDialog,
              icon: const Icon(Icons.add),
              label: const Text('کلمه کلیدی جدید'),
            )
          : null,
    );
  }

  List<dynamic> get chronologicalReceipts {
    final list = List<dynamic>.from(filteredReceipts);
    list.sort((a, b) {
      final idA = a['id'] ?? 0;
      final idB = b['id'] ?? 0;
      return idA.compareTo(idB); // ترتیب زمانی: از قدیمی به جدید (اسکرول به بالا برای قدیمی‌ترها)
    });
    return list;
  }

  String toPersianDigits(String input) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    for (int i = 0; i < english.length; i++) {
      input = input.replaceAll(english[i], persian[i]);
    }
    return input;
  }

  String extractDateHeader(Map<String, dynamic> item) {
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

  String extractTimeBadge(Map<String, dynamic> item) {
    final d = (item['date_str'] ?? item['date'] ?? item['created_at'] ?? '').toString();
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(d);
    if (match != null) {
      return match.group(1)!;
    }
    return '12:00';
  }

  Widget _buildCompletedOrdersTab(ThemeData theme) {
    final completedCount = receipts.where((r) => r['status'] == 'completed' || (r['score'] ?? 0) >= 90).length;
    final list = chronologicalReceipts.where((item) {
      if (onlyCompletedFilter) {
        return item['status'] == 'completed' || (item['score'] ?? 0) >= 90;
      }
      return true;
    }).toList();

    return Column(
      children: [
        SummaryHeaderWidget(
          totalCount: receipts.length,
          totalAmount: totalAmount,
          totalDiscounts: totalDiscounts,
        ),
        FilterSearchCard(
          searchQuery: searchQuery,
          onSearchChanged: (val) => setState(() => searchQuery = val),
          onlyCompletedFilter: onlyCompletedFilter,
          onOnlyCompletedChanged: (val) => setState(() => onlyCompletedFilter = val ?? false),
          totalCount: receipts.length,
          completedCount: completedCount,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage.isNotEmpty
                  ? _buildErrorWidget()
                  : list.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined, size: 54, color: Colors.grey),
                                SizedBox(height: 12),
                                Text(
                                  'هیچ پیامی با این فیلتر یافت نشد.\nمی‌توانید چک‌باکس سفارشات تکمیل‌شده را خاموش کنید.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            if (isLoadingMore)
                              Container(
                                color: Colors.purple.shade50,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 8),
                                    Text('در حال بارگذاری پیام‌های قدیمی‌تر...', style: TextStyle(fontSize: 11, color: Colors.purple)),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: () => fetchReceipts(),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFECEFF1),
                                  ),
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    itemCount: list.length,
                                    itemBuilder: (context, index) {
                                      final item = list[index];
                                      final currentDate = DateFormatter.extractDateHeader(item);

                                      String? dateHeaderToShow;
                                      if (index == 0) {
                                        dateHeaderToShow = currentDate;
                                      } else {
                                        final prevDate = DateFormatter.extractDateHeader(list[index - 1]);
                                        if (prevDate != currentDate) {
                                          dateHeaderToShow = currentDate;
                                        }
                                      }

                                      return RubikaChatBubble(
                                        item: item,
                                        showDateHeader: dateHeaderToShow,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
        ),
      ],
    );
  }





  Widget _buildAutoRulesTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.deepPurple.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.deepPurple.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'اگر پیامی حاوی کلمه کلیدی زیر باشد، ربات خودکار پاسخ تعیین‌شده را در روبیکا ارسال می‌کند.',
                      style: TextStyle(color: Colors.deepPurple.shade900, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: autoRules.isEmpty
                ? const Center(
                    child: Text(
                      'هیچ قانون پاسخگویی ثبت نشده است.\nبر روی دکمه «کلمه کلیدی جدید» کلیک کنید.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: autoRules.length,
                    itemBuilder: (context, index) {
                      final rule = autoRules[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade100,
                            child: const Icon(Icons.chat_bubble_outline, color: Colors.purple),
                          ),
                          title: Row(
                            children: [
                              const Text('کلمه کلیدی: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                rule['keyword'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'پاسخ خودکار: ${rule['response_text']}',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => deleteAutoRule(rule['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }





  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => fetchAllData(),
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      ),
    );
  }





  void showAddRuleDialog() {
    final kwController = TextEditingController();
    final respController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعریف کلمه کلیدی و پاسخ خودکار'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: kwController,
                decoration: const InputDecoration(
                  labelText: 'کلمه کلیدی (مثلاً: تخفیف، شماره کارت، ساعت کاری)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: respController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'متن پاسخ خودکار روبیکا',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () {
                final kw = kwController.text.trim();
                final resp = respController.text.trim();
                if (kw.isNotEmpty && resp.isNotEmpty) {
                  addAutoRule(kw, resp);
                  Navigator.pop(context);
                }
              },
              child: const Text('ذخیره قانون'),
            ),
          ],
        ),
      ),
    );
  }

  void showSmmOrderDialog() {
    showSmmOrderDialogWithService("7");
  }

  void showSmmOrderDialogWithService(String initialServiceId) {
    final serviceController = TextEditingController(text: initialServiceId);
    final linkController = TextEditingController(text: "https://rubika.ir/");
    final qtyController = TextEditingController(text: "1000");

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ثبت سفارش خدمات rubika1.ir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: serviceController,
                decoration: const InputDecoration(
                  labelText: 'کد سرویس (مثلاً 7 برای سین پست)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: linkController,
                decoration: const InputDecoration(
                  labelText: 'لینک پست / آیدی روبینو / کانال',
                  hintText: 'https://rubika.ir/post/xxxxx',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'تعداد سفارش (مثلاً 1000)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () {
                final sId = serviceController.text.trim();
                final link = linkController.text.trim();
                final qty = int.tryParse(qtyController.text.trim()) ?? 1000;
                if (sId.isNotEmpty && link.isNotEmpty) {
                  Navigator.pop(context);
                  submitSmmOrder(sId, link, qty);
                }
              },
              child: const Text('ثبت و ارسال سفارش'),
            ),
          ],
        ),
      ),
    );
  }

  void showServerUrlDialog() {
    final controller = TextEditingController(text: baseServerUrl);
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تنظیمات آدرس سرور پایتون'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'آدرس سرور پایه (Base Server URL)',
                      hintText: 'http://10.0.2.2:5050 یا http://localhost:5050',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('انتخاب سریع آدرس:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.android, size: 16),
                        label: const Text('شبیه‌ساز (10.0.2.2)'),
                        onPressed: () {
                          controller.text = 'http://10.0.2.2:5050';
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.computer, size: 16),
                        label: const Text('لوکال‌هاست (localhost)'),
                        onPressed: () {
                          controller.text = 'http://localhost:5050';
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'نکته: برای گوشی واقعی، IP سیستم خود در شبکه local (مثلاً http://192.168.1.50:5050) را وارد کنید.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('انصراف'),
                ),
                ElevatedButton(
                  onPressed: () {
                    String url = controller.text.trim();
                    if (url.endsWith('/')) {
                      url = url.substring(0, url.length - 1);
                    }
                    setState(() {
                      baseServerUrl = url;
                    });
                    _saveServerUrl(url);
                    Navigator.pop(context);
                    fetchAllData();
                  },
                  child: const Text('ذخیره و تلاش مجدد'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
