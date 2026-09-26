import server
import json

server.init_db()

# پیام تست ارسال به کانال سفارشات امیر و خاتون
test_channel_message = """
کانال سفارشات امیر و خاتون 🌹
تست ثبت خودکار سفارش و برسی هوشمند:

سیدرضاحسینی
گرگان ایرانمهر بالا ابوذر ۴۵ منزل سیدحسن حسینی
09119707011
۱ عدد ماشین پشم چین اسپرینت
"""

parsed = server.categorize_and_parse({
    "msg_id": "14050704_TEST_001",
    "raw_text": test_channel_message.strip(),
    "sender": "سیدرضاحسینی",
    "receiver": "کانال سفارشات امیر و خاتون"
})

if parsed:
    record_id = server.save_receipt(parsed)
    server.get_takhfif_module_export()

    print("==================================================")
    print("🚀 [ارسال تست به کانال سفارشات امیر و خاتون]")
    print("==================================================")
    print(f"📌 شناسه ثبت دیتابیس: {record_id}")
    print(f"👤 مشتری: {parsed.get('customer_name')}")
    print(f"📞 شماره تماس: {parsed.get('phones')}")
    print(f"📍 آدرس: {parsed.get('address')}")
    print(f"📦 اقلام سفارش: {parsed.get('order_item')}")
    print(f"⭐ امتیاز آنالیز: {parsed.get('score')}٪")
    print(f"🚥 وضعیت فاکتور: {parsed.get('status')}")
    print(f"⚠️ پارامترهای غایب: {parsed.get('missing_params')}")
    print(f"📩 ریپلای هوشمند صادرشده جهت ارسال در کانال:")
    print("-" * 50)
    print(parsed.get('reply_text'))
    print("-" * 50)
    print("✅ خروجی takhfif_module_export.json بروزرسانی شد.")
else:
    print("❌ خطا در تحلیل پیام تست.")
