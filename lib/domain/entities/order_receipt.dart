class OrderReceipt {
  final int id;
  final String msgId;
  final String category;
  final String bankName;
  final num amount;
  final String trackingNumber;
  final String sender;
  final String phones;
  final String customerName;
  final String address;
  final String orderItem;
  final String rawText;
  final num discountAmount;
  final int score;
  final String status;
  final String missingParams;
  final String replyText;

  OrderReceipt({
    required this.id,
    required this.msgId,
    required this.category,
    required this.bankName,
    required this.amount,
    required this.trackingNumber,
    required this.sender,
    required this.phones,
    required this.customerName,
    required this.address,
    required this.orderItem,
    required this.rawText,
    required this.discountAmount,
    required this.score,
    required this.status,
    required this.missingParams,
    required this.replyText,
  });
}
