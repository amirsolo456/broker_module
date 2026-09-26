import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

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

class _ReceiptsHomePageState extends State<ReceiptsHomePage> with SingleTickerProviderStateMixin {
  // آدرس پایه هماهنگ با شبیه‌ساز اندروید (10.0.2.2) و سیستم خانگی (localhost)
  static String get defaultBaseHost => Platform.isAndroid ? "http://10.0.2.2:5050" : "http://localhost:5050";

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
  String errorMessage = "";
  String searchQuery = "";
  int selectedCategoryIndex = 0;

  late TabController _tabController;
  Timer? autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    baseServerUrl = defaultBaseHost;
    _tabController = TabController(length: 3, vsync: this);
    _loadSavedServerUrl();
    autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => fetchAllData(isSilent: true));
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
    _tabController.dispose();
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
    if (!isSilent) {
      setState(() {
        isLoading = true;
        errorMessage = "";
      });
    }

    try {
      final response = await http.get(Uri.parse(serverUrl)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true) {
          setState(() {
            receipts = body['data'] ?? [];
            isLoading = false;
            errorMessage = "";
          });
        }
      } else {
        if (!isSilent) {
          setState(() {
            errorMessage = "خطا در دریافت اطلاعات صورتحساب‌ها (${response.statusCode})";
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!isSilent) {
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
      if (selectedCategoryIndex == 1 && item['category'] != 'bank_receipt') return false;
      if (selectedCategoryIndex == 2 && item['category'] != 'customer_order') return false;

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
        title: const Text(
          'مدیریت صورتحساب و پنل خدمات روبیکا',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.receipt_long),
              text: 'صورتحساب‌ها (${receipts.length})',
            ),
            Tab(
              icon: const Icon(Icons.smart_toy),
              text: 'پاسخگوی هوشمند (${autoRules.length})',
            ),
            const Tab(
              icon: Icon(Icons.shopping_cart),
              text: 'خدمات rubika1.ir',
            ),
          ],
        ),
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReceiptsTab(theme),
          _buildAutoRulesTab(theme),
          _buildSmmTab(theme),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          if (_tabController.index == 1) {
            return FloatingActionButton.extended(
              onPressed: showAddRuleDialog,
              icon: const Icon(Icons.add),
              label: const Text('کلمه کلیدی جدید'),
            );
          } else if (_tabController.index == 2) {
            return FloatingActionButton.extended(
              onPressed: showSmmOrderDialog,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('ثبت سفارش خدمات'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
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

  String extractDateHeader(Map<String, dynamic> item) {
    final d = (item['date_str'] ?? item['date'] ?? item['created_at'] ?? '').toString();
    if (d.contains('1405/07/02') || d.contains('1405-07-02')) return 'پنجشنبه، ۲ مهر ۱۴۰۵';
    if (d.contains('1405/07/03') || d.contains('1405-07-03')) return 'جمعه، ۳ مهر ۱۴۰۵';
    if (d.contains('1405/07/04') || d.contains('1405-07-04')) return 'شنبه، ۴ مهر ۱۴۰۵';

    final match = RegExp(r'(140\d[/\-]\d{1,2}[/\-]\d{1,2})').firstMatch(d);
    if (match != null) {
      return 'تاریخ: ${match.group(1)}';
    }
    return 'پیام‌های ثبت‌شده';
  }

  String extractTimeBadge(Map<String, dynamic> item) {
    final d = (item['date_str'] ?? item['date'] ?? item['created_at'] ?? '').toString();
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(d);
    if (match != null) {
      return match.group(1)!;
    }
    return '12:00';
  }

  Widget _buildReceiptsTab(ThemeData theme) {
    final list = chronologicalReceipts;

    return Column(
      children: [
        _buildSummaryHeader(theme),
        _buildFilterAndSearchSection(),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage.isNotEmpty
                  ? _buildErrorWidget()
                  : list.isEmpty
                      ? _buildEmptyWidget()
                      : RefreshIndicator(
                          onRefresh: () => fetchReceipts(),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFECEFF1), // پس‌زمینه گفتگو شبیه روبیکا
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final item = list[index];
                                final currentDate = extractDateHeader(item);

                                String? dateHeaderToShow;
                                if (index == 0) {
                                  dateHeaderToShow = currentDate;
                                } else {
                                  final prevDate = extractDateHeader(list[index - 1]);
                                  if (prevDate != currentDate) {
                                    dateHeaderToShow = currentDate;
                                  }
                                }

                                return _buildRubikaChatBubble(item, dateHeaderToShow);
                              },
                            ),
                          ),
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

  Widget _buildSmmTab(ThemeData theme) {
    final balance = smmBalanceData != null ? (smmBalanceData!['balance'] ?? '0') : 'در حال استعلام...';
    final currency = smmBalanceData != null ? (smmBalanceData!['currency'] ?? 'تومان') : '';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.indigo.shade900,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.account_balance_wallet, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('موجودی پنل rubika1.ir', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '$balance $currency',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      fetchSmmBalance();
                      fetchSmmServices();
                    },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('استعلام مجدد'),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('خدمات قابل سفارش rubika1.ir:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton(
                onPressed: () => fetchSmmServices(),
                child: const Text('بارگذاری لیست سرویس‌ها'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: smmServices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_download_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('برای مشاهده سرویس‌ها، روی دکمه «بارگذاری لیست سرویس‌ها» کلیک کنید.'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => fetchSmmServices(),
                          child: const Text('دریافت لیست سرویس‌ها'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: smmServices.length,
                    itemBuilder: (context, index) {
                      final s = smmServices[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Text('کد سرویس: ${s['service']} | حداقل: ${s['min']} - حداکثر: ${s['max']} | نرخ: ${s['rate']} تومان'),
                          trailing: ElevatedButton(
                            onPressed: () => showSmmOrderDialogWithService(s['service'].toString()),
                            child: const Text('سفارش'),
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

  Widget _buildSummaryHeader(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withAlpha(76),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('تعداد صورتحساب', '${receipts.length} عدد', Icons.receipt_long),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildStatItem('مجموع مبالغ', '${formatCurrency(totalAmount)} ریال', Icons.account_balance_wallet),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildStatItem('تخفیف‌های محاسبه‌شده', '${formatCurrency(totalDiscounts)} ریال', Icons.discount),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildFilterAndSearchSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => searchQuery = val),
            decoration: InputDecoration(
              hintText: 'جستجو در شماره پیگیری، نام بانک، مشتری یا تلفن...',
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryFilterChip(0, 'همه پیام‌ها (${receipts.length})'),
                const SizedBox(width: 8),
                _buildCategoryFilterChip(1, 'رسیدهای بانکی'),
                const SizedBox(width: 8),
                _buildCategoryFilterChip(2, 'سفارشات مشتریان'),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip(int index, String label) {
    final isSelected = selectedCategoryIndex == index;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      onSelected: (bool selected) {
        setState(() {
          selectedCategoryIndex = index;
        });
      },
    );
  }

  Widget _buildRubikaChatBubble(Map<String, dynamic> item, String? showDateHeader) {
    final isBank = item['category'] == 'bank_receipt' || item['type'] == 'bank_receipt';
    final rawText = (item['raw_text'] ?? '').toString();
    final custName = (item['customer_name'] ?? item['sender'] ?? '').toString();
    final bankName = (item['bank_name'] ?? 'بانک').toString();
    final amount = item['amount'] ?? 0;
    final discount = item['discount_amount'] ?? 0;
    final tracking = (item['tracking_number'] ?? '').toString();
    final phones = (item['phones'] ?? '').toString();
    final address = (item['address'] ?? '').toString();
    final orderItem = (item['order_item'] ?? '').toString();
    final timeStr = extractTimeBadge(item);

    return Column(
      children: [
        if (showDateHeader != null)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.32),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              showDateHeader,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
            margin: const EdgeInsets.only(bottom: 10, right: 4, left: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isBank ? const Color(0xFFE8F5E9) : const Color(0xFFF3E5F5), // Green tint for Bank, Soft Purple for Order
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Peer Name)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: isBank ? Colors.green.shade700 : Colors.deepPurple,
                          child: Icon(
                            isBank ? Icons.account_balance : Icons.person,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isBank ? bankName : (custName.isNotEmpty ? custName : 'مجموعه اصلاح نژاد دام خاتون'),
                          style: TextStyle(
                            color: isBank ? Colors.green.shade900 : Colors.deepPurple.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isBank ? Colors.green.shade200 : Colors.purple.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isBank ? 'رسید پرداخت' : 'سفارش ثبت‌شده',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBank ? Colors.green.shade900 : Colors.purple.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Raw Message Text
                SelectableText(
                  rawText.isNotEmpty ? rawText : 'متن پیام خالی است',
                  style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.black87),
                ),
                const SizedBox(height: 10),

                // Structured summary badge
                if (isBank) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (amount > 0)
                          _buildBubbleField('مبلغ رسید:', '${formatCurrency(amount)} ریال', isBold: true),
                        if (tracking.isNotEmpty)
                          _buildBubbleField('شماره پیگیری:', tracking),
                        if (discount > 0)
                          _buildBubbleField('تخفیف ۵٪ محاسبه‌شده:', '${formatCurrency(discount)} ریال', highlight: true),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.purple.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (custName.isNotEmpty)
                          _buildBubbleField('نام مشتری:', custName),
                        if (phones.isNotEmpty)
                          _buildBubbleField('شماره تماس:', phones),
                        if (orderItem.isNotEmpty)
                          _buildBubbleField('اقلام سفارش:', orderItem, isBold: true),
                        if (address.isNotEmpty)
                          _buildBubbleField('آدرس:', address),
                      ],
                    ),
                  ),
                ],

                // Score & Status Section
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (item['status'] == 'completed' || (item['score'] ?? 0) >= 97) ? Colors.green.shade100 : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (item['status'] == 'completed' || (item['score'] ?? 0) >= 97) ? Colors.green.shade400 : Colors.orange.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (item['status'] == 'completed' || (item['score'] ?? 0) >= 97) ? Icons.check_circle : Icons.hourglass_top,
                            size: 13,
                            color: (item['status'] == 'completed' || (item['score'] ?? 0) >= 97) ? Colors.green.shade800 : Colors.orange.shade900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            (item['status'] == 'completed' || (item['score'] ?? 0) >= 97) ? 'کامل (تایید خودکار)' : 'پندینگ (نمره: ${item['score'] ?? 0}٪)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: (item['status'] == 'completed' || (item['score'] ?? 0) >= 97) ? Colors.green.shade900 : Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((item['status'] != 'completed' && (item['score'] ?? 0) < 97) && (item['reply_text'] ?? '').toString().isNotEmpty)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: item['reply_text'].toString()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('متن ریپلای روبیکا در حافظه کپی شد')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.deepOrange.shade300),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.reply, size: 12, color: Colors.deepOrange),
                              SizedBox(width: 4),
                              Text(
                                'کپی ریپلای روبیکا',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if ((item['status'] != 'completed' && (item['score'] ?? 0) < 97) && (item['missing_params'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'پارامترهای غایب: ${item['missing_params']}',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                  ),
                ],

                const SizedBox(height: 6),
                // Time Badge & Read Checks
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all,
                      size: 14,
                      color: isBank ? Colors.green.shade700 : Colors.deepPurple,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubbleField(String label, String value, {bool isBold = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              color: highlight ? Colors.amber.shade900 : Colors.grey.shade700,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isBold || highlight ? FontWeight.bold : FontWeight.normal,
                color: highlight ? Colors.amber.shade900 : Colors.black87,
              ),
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

  Widget _buildEmptyWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 54, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'هنوز هیچ صورتحسابی دریافت نشده است.\nدر حال پایش روبیکا...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
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
