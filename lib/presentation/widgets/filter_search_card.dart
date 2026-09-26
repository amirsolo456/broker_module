import 'package:flutter/material.dart';

class FilterSearchCard extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final bool onlyCompletedFilter;
  final ValueChanged<bool?> onOnlyCompletedChanged;
  final int totalCount;
  final int completedCount;

  const FilterSearchCard({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onlyCompletedFilter,
    required this.onOnlyCompletedChanged,
    required this.totalCount,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Column(
        children: [
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'جستجو در شماره پیگیری، نام بانک، مشتری یا تلفن...',
              prefixIcon: const Icon(Icons.search, color: Colors.purple),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => onOnlyCompletedChanged(!onlyCompletedFilter),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Checkbox(
                    value: onlyCompletedFilter,
                    activeColor: Colors.green.shade800,
                    onChanged: onOnlyCompletedChanged,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          onlyCompletedFilter ? Icons.verified : Icons.all_inbox,
                          size: 18,
                          color: onlyCompletedFilter ? Colors.green.shade800 : Colors.purple,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          onlyCompletedFilter
                              ? 'فقط نمایش سفارشات تکمیل‌شده ۱۰۰٪ ($completedCount)'
                              : 'نمایش همه پیام‌ها ($totalCount)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: onlyCompletedFilter ? Colors.green.shade900 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
