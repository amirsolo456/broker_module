import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/date_formatter.dart';
import 'status_badge.dart';

class RubikaChatBubble extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? showDateHeader;

  const RubikaChatBubble({
    super.key,
    required this.item,
    this.showDateHeader,
  });

  @override
  Widget build(BuildContext context) {
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
    final timeStr = DateFormatter.extractTimeBadge(item);
    final isCompleted = item['status'] == 'completed' || (item['score'] ?? 0) >= 90;
    final replyText = (item['reply_text'] ?? '').toString();
    final missingParams = (item['missing_params'] ?? '').toString();

    return Column(
      children: [
        if (showDateHeader != null)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 14, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x803E5C4B),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  )
                ],
              ),
              child: Text(
                showDateHeader!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IRANSans',
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
            margin: const EdgeInsets.only(bottom: 10, right: 4, left: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isBank ? const Color(0xFFE8F5E9) : const Color(0xFFF3E5F5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

                SelectableText(
                  rawText.isNotEmpty ? rawText : 'متن پیام خالی است',
                  style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.black87),
                ),
                const SizedBox(height: 10),

                if (isBank) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (amount > 0)
                          _buildBubbleField('مبلغ رسید:', '${DateFormatter.formatCurrency(amount)} ریال', isBold: true),
                        if (tracking.isNotEmpty)
                          _buildBubbleField('شماره پیگیری:', tracking),
                        if (discount > 0)
                          _buildBubbleField('تخفیف ۵٪ محاسبه‌شده:', '${DateFormatter.formatCurrency(discount)} ریال', highlight: true),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
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

                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusBadge(isCompleted: isCompleted, score: item['score'] ?? 0),
                    if (!isCompleted && replyText.isNotEmpty)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: replyText));
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
                if (!isCompleted && missingParams.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'پارامترهای غایب: $missingParams',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                  ),
                ],

                const SizedBox(height: 6),
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
}
