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
        fontFamily: 'Roboto',
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

  Widget _buildReceiptsTab(ThemeData theme) {
    return Column(
      children: [
        _buildSummaryHeader(theme),
        _buildFilterAndSearchSection(),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage.isNotEmpty
                  ? _buildErrorWidget()
                  : filteredReceipts.isEmpty
                      ? _buildEmptyWidget()
                      : RefreshIndicator(
                          onRefresh: () => fetchReceipts(),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filteredReceipts.length,
                            itemBuilder: (context, index) {
                              return _buildReceiptCard(filteredReceipts[index]);
                            },
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

  Widget _buildReceiptCard(Map<String, dynamic> item) {
    final isBank = item['category'] == 'bank_receipt';
    final amount = item['amount'] ?? 0;
    final discount = item['discount_amount'] ?? 0;
    final tracking = item['tracking_number'] ?? 'ثبت‌نشده';
    final bankName = item['bank_name'] ?? (isBank ? 'بانک نامشخص' : 'سفارش');
    final sender = item['sender'] ?? item['customer_name'] ?? 'نامشخص';
    final dateStr = item['date_str'] ?? item['created_at'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isBank ? Colors.green.shade50 : Colors.blue.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isBank ? Icons.account_balance : Icons.shopping_bag,
                        color: isBank ? Colors.green.shade700 : Colors.blue.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bankName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (dateStr.isNotEmpty)
                          Text(
                            dateStr,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBank ? Colors.green.shade100 : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isBank ? 'رسید بانکی' : 'سفارش',
                    style: TextStyle(
                      color: isBank ? Colors.green.shade900 : Colors.blue.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              ],
            ),
            const Divider(height: 20),

            if (isBank) ...[
              _buildDetailRow('مبلغ پرداخت شده:', '${formatCurrency(amount)} ریال', isBold: true),
              _buildDetailRow('شماره پیگیری / مرجع:', tracking),
              if (item['destination_iban'] != null)
                _buildDetailRow('شبا مقصد:', item['destination_iban']),
              _buildDetailRow('فرستنده / پرداخت‌کننده:', sender),
            ] else ...[
              _buildDetailRow('نام مشتری:', sender),
              if (item['phones'] != null && item['phones'].isNotEmpty)
                _buildDetailRow('شماره تماس:', item['phones']),
            ],

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.amber, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'تخفیف پیشنهادی ماژول:',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                      ),
                    ],
                  ),
                  Text(
                    '${formatCurrency(discount)} ریال',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item['raw_text'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('متن صورتحساب در حافظه کپی شد')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('کپی متن'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showRawDialog(item),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('مشاهده کامل'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          SelectableText(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 13 : 12,
              color: isBold ? Colors.black87 : Colors.grey.shade900,
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

  void _showRawDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('جزئیات کامل صورتحساب'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('متن خام استخراج شده از روبیکا:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    item['raw_text'] ?? '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('اطلاعات طبقه‌بندی شده:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(item),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF0D47A1)),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن'),
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
