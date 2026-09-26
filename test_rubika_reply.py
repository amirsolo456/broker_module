import server
import json

server.init_db()

incomplete_records = [r for r in server.get_all_receipts() if r.get('score', 0) >= 80 and r.get('score', 0) < 90]

if incomplete_records:
    test_msg = incomplete_records[0]
    msg_id = test_msg.get('msg_id')
    cust_name = test_msg.get('customer_name')
    reply_text = test_msg.get('reply_text')

    print(f"🎯 [آزمایش ریپلای روبیکا] پیام انتخاب‌شده:")
    print(f"📌 کد پیام: {msg_id}")
    print(f"👤 فرستنده: {cust_name}")
    print(f"⭐ نمره: {test_msg.get('score')}٪")
    print(f"📩 متن پاسخ خودکار تولیدشده جهت ارسال در کانال:")
    print("-" * 50)
    print(reply_text)
    print("-" * 50)

    # ارسال تست به rubika1.ir API
    res = server.add_rubika1_order(service_id=1, link=f"msg_id:{msg_id}", quantity=1, comments=reply_text)
    print("🚀 نتیجه پاسخ لایه ارتباطی روبیکا:")
    print(json.dumps(res, ensure_ascii=False, indent=2))
else:
    print("هیچ پیام ناقصی با امتیاز ۸۰ تا ۹۰ یافت نشد.")
