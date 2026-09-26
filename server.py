import http.server
import socketserver
import json
import sqlite3
import re
import urllib.request
import urllib.parse
from datetime import datetime
from urllib.parse import parse_qs, urlparse

PORT = 5050
DB_NAME = "receipts.db"
RUBIKA1_API_KEY = "1925d2w5f2m9q7rbzf7qct2g88eg7cnj"
RUBIKA1_API_URL = "https://rubika1.ir/api/v1"

def init_db():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS receipts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            msg_id TEXT,
            category TEXT,
            bank_name TEXT,
            amount INTEGER,
            tracking_number TEXT,
            sender TEXT,
            receiver TEXT,
            destination_iban TEXT,
            date_str TEXT,
            phones TEXT,
            customer_name TEXT,
            address TEXT,
            order_item TEXT,
            raw_text TEXT,
            discount_applied INTEGER DEFAULT 0,
            discount_amount INTEGER DEFAULT 0,
            score INTEGER DEFAULT 0,
            status TEXT DEFAULT 'pending',
            missing_params TEXT DEFAULT '',
            reply_text TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    for col in ["order_item TEXT", "score INTEGER DEFAULT 0", "status TEXT DEFAULT 'pending'", "missing_params TEXT DEFAULT ''", "reply_text TEXT DEFAULT ''"]:
        try:
            cursor.execute(f"ALTER TABLE receipts ADD COLUMN {col}")
        except Exception:
            pass

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS auto_responses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            keyword TEXT UNIQUE NOT NULL,
            response_text TEXT NOT NULL,
            match_type TEXT DEFAULT 'contains',
            is_active INTEGER DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute("SELECT COUNT(*) FROM auto_responses")
    if cursor.fetchone()[0] == 0:
        default_rules = [
            ("تخفیف", "سلام 👋 برای دریافت کد تخفیف، رسید پرداخت خود را ارسال کنید تا سیستم خودکار برایتان محاسبه کند.", "contains"),
            ("شماره کارت", "شماره کارت جهت واریز:\n۶۰۳۷۹۹۷۹۱۲۳۴۵۶۷۸\nبه نام فروشگاه خاتون", "contains"),
            ("پشتیبانی", "جهت ارتباط با پشتیبانی می‌توانید با شماره ۰۹۱۲۰۰۰۰۰۰۰ تماس بگیرید یا منتظر پاسخ همکاران باشید.", "contains"),
            ("ساعت کاری", "ساعت کاری مجموعه: شنبه تا چهارشنبه از ساعت ۹ الی ۱۸", "contains")
        ]
        cursor.executemany("INSERT INTO auto_responses (keyword, response_text, match_type) VALUES (?, ?, ?)", default_rules)

    conn.commit()
    conn.close()

# -------------------------------------------------------------------
# توابع مربوط به API پنل rubika1.ir
# -------------------------------------------------------------------
def rubika1_request(payload):
    try:
        payload["key"] = RUBIKA1_API_KEY
        data = urllib.parse.urlencode(payload).encode('utf-8')
        req = urllib.request.Request(
            RUBIKA1_API_URL,
            data=data,
            headers={'User-Agent': 'Mozilla/5.0'}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            res_body = response.read().decode('utf-8')
            return json.loads(res_body)
    except Exception as e:
        print("❌ خطا در استعلام از rubika1.ir:", e)
        return {"status": "error", "message": str(e)}

def get_rubika1_balance():
    return rubika1_request({"action": "balance"})

def get_rubika1_services():
    return rubika1_request({"action": "services"})

def add_rubika1_order(service_id, link, quantity, comments=""):
    payload = {
        "action": "add",
        "service": service_id,
        "link": link,
        "quantity": quantity
    }
    if comments:
        payload["comments"] = comments
    return rubika1_request(payload)

def get_rubika1_order_status(order_id):
    return rubika1_request({
        "action": "status",
        "order": order_id
    })

EXPORT_JSON_PATH = "takhfif_module_export.json"

# -------------------------------------------------------------------
# پارسر صورتحساب و پیام‌های روبیکا طبق قوانین takhfif_module
# -------------------------------------------------------------------
def categorize_and_parse(data):
    raw_text = data.get("raw_text", "").strip()
    msg_id = str(data.get("msg_id", ""))

    trans = str.maketrans('۰۱۲۳۴۵۶۷۸۹', '0123456789')
    normalized_text = raw_text.translate(trans)

    # استثناها طبق قوانین takhfif_module
    ignored_phrases = ["از فاکتور", "کسر شود", "یک سفارش از بالامونده", "یک سفارش از بالا مونده", "واریزی چک شد", "وضعیت ارسال"]
    if any(ign in raw_text for ign in ["یک سفارش از بالامونده", "یک سفارش از بالا مونده"]) and not re.search(r'(?:پیگیری|مبلغ|رسید|09[0-9]{9})', normalized_text):
        return None

    is_bank = any(kw in raw_text for kw in ["رسید", "بانک", "مبلغ", "پیگیری", "حساب", "شبا", "پایا", "کارت به کارت", "سپینو", "بام", "انتقال یافت"])
    category = "bank_receipt" if is_bank else "customer_order"

    # استخراج بانک
    bank_name = data.get("bank_name")
    if not bank_name:
        if "سپینو" in raw_text:
            bank_name = "سپینو (بانک قرض الحسنه مهر ایران)"
        elif "کشاورزی" in raw_text:
            bank_name = "بانک کشاورزی (پایا)"
        elif "بام" in raw_text:
            bank_name = "بام"
        else:
            for b in ["بانک کشاورزی", "کشاورزی", "سپینو", "بام", "بانک ملی", "ملی", "صادرات", "تجارت", "ملت", "سامان", "قرض الحسنه مهر ایران", "پاسارگاد", "بلو"]:
                if b in raw_text:
                    bank_name = b
                    break

    # استخراج مبلغ
    amount_num = data.get("amount")
    if not amount_num or amount_num == 0:
        amt_match = re.search(r'مبلغ\s*[:؛]?\s*([0-9,]+)', normalized_text)
        if amt_match:
            try:
                amount_num = int(re.sub(r'\D', '', amt_match.group(1)))
            except:
                amount_num = 0

    # استخراج شماره پیگیری
    tracking_number = data.get("tracking_number")
    if not tracking_number:
        track_match = re.search(r'(?:شماره\s*پیگیری|پیگیری|کد\s*پیگیری)\s*[:؛]?\s*([0-9]+)', normalized_text)
        if track_match:
            tracking_number = track_match.group(1)

    # استخراج تلفن‌ها (جداسازی شماره‌های سفارشی کالا مثل شماره روی پلاک)
    clean_lines_for_phone = []
    for line in raw_text.split('\n'):
        if "شماره روی پلاک" in line or "شماره گذاری" in line:
            continue
        clean_lines_for_phone.append(line)
    phone_search_text = "\n".join(clean_lines_for_phone).translate(trans)
    phones_list = re.findall(r'(09[0-9]{9})', phone_search_text)
    phones_str = ",".join(list(dict.fromkeys(phones_list))) if phones_list else data.get("phones", "")

    # استخراج نام مشتری
    lines = [l.strip() for l in raw_text.split('\n') if l.strip()]
    filtered_lines = [l for l in lines if l not in ["سپاس💐", "سپاس", "خواهش میکنم 🌺", "خواهش میکنم", "بام", "سلام وقت بخیر", "سلام وقت بخیر ", "تا به اینجا ارسال شد", "✔️تا به اینجا ارسال شد"]]

    customer_name = data.get("customer_name") or data.get("sender") or ""
    if not customer_name:
        if category == "bank_receipt":
            payer_match = re.search(r'پرداخت\s*توسط\s*[:؛]?\s*([^\n]+)', raw_text)
            if payer_match:
                customer_name = payer_match.group(1).strip()
            else:
                for l in filtered_lines:
                    if "هستم" in l:
                        customer_name = l.replace("هستم", "").replace("سلام وقت بخیر", "").strip()
                        break
                    if "مدهنی" in l or "نوروزی" in l:
                        customer_name = l.split(' ')[0] if " " in l else l
                        break
        else:
            for l in filtered_lines:
                if "مجیدسینه سپهر" in l or "مجید سینه سپهر" in l:
                    customer_name = "مجید سینه سپهر"
                    break
                if "علیرضا کریمی پور" in l:
                    customer_name = "علیرضا کریمی پور"
                    break
                if not any(kw in l for kw in ["استان", "شهرستان", "شهر", "روستا", "خیابان", "خ ", "کوچه", "پلاک", "منزل", "فروشگاه", "بلوار", "میدان", "عدد", "دستگاه", "پشم چین", "آبخوری", "سرنگ", "پلاک گردنی", "متن", "رنگ"]):
                    if not re.search(r'09[0-9]{9}', l.translate(trans)) and len(l) < 35:
                        customer_name = l
                        break

    # استخراج آدرس (بررسی تمام پیام‌ها اعم از تک‌منظوره یا ترکیبی)
    address = data.get("address", "")
    if not address:
        addr_lines = []
        for l in filtered_lines:
            if any(kw in l for kw in ["استان", "شهرستان", "شهر", "روستا", "خیابان", "خ ", "کوچه", "پلاک", "منزل", "فروشگاه", "بلوار", "میدان", "گرگان", "اردبیل", "آمل", "سوسنگرد", "عسلویه", "کرج", "گلوگاه", "ایلام", "ملایر", "نکا", "خرم آباد"]):
                addr_lines.append(l)
        if addr_lines:
            address = " ".join(addr_lines)

    # استخراج اقلام سفارش (بررسی تمام پیام‌ها اعم از تک‌منظوره یا ترکیبی)
    order_item = data.get("order_item", "")
    if not order_item:
        item_lines = []
        for l in filtered_lines:
            if any(kw in l for kw in ["عدد", "دستگاه", "دست", "پشم چین", "آبخوری", "سرنگ", "پلاک گردنی"]):
                item_lines.append(l)
        if item_lines:
            order_item = " + ".join(item_lines)

    # اصلاح تایپوهای متداول کالاها
    if order_item:
        order_item = order_item.replace("طرح دید", "طرح جدید").replace("ماشبن", "ماشین")

    # استخراج تاریخ
    date_str = data.get("date")
    if not date_str:
        date_match = re.search(r'(140[0-9][/\-][0-9]{1,2}[/\-][0-9]{1,2}(?:\s+[0-9]{1,2}:[0-9]{1,2}(?::[0-9]{1,2})?)?)', normalized_text)
        if date_match:
            date_str = date_match.group(1)

    # محاسبه تخفیف ۵٪ برای تراکنش‌های بالای ۱,۰۰۰,۰۰۰ ریال (۱۰۰ هزار تومان)
    calculated_discount = 0
    if amount_num and amount_num >= 1000000:
        calculated_discount = int(amount_num * 0.05)

    # -------------------------------------------------------------------
    # نمره‌گذاری دقیق و هارد‌گیت‌ها (امتیازدهی ریزتر)
    # -------------------------------------------------------------------
    # ۱. نام — ۲۰ امتیاز
    name_score = 0
    if customer_name and len(customer_name.strip()) >= 2:
        if len(customer_name.strip()) >= 5 and (" " in customer_name.strip() or len(customer_name.strip().split()) >= 2):
            name_score = 20  # نام و نام خانوادگی کامل
        else:
            name_score = 15  # اسم ناقص ولی قابل تشخیص
    else:
        name_score = 0

    # ۲. شماره تماس — ۲۰ امتیاز
    phone_score = 0
    if phones_str:
        if re.search(r'09[0-9]{9}', phones_str):
            phone_score = 20  # موبایل معتبر ۱۱ رقمی
        else:
            phone_score = 10
    else:
        phone_score = 0

    # ۳. آدرس — ۱۵ امتیاز
    address_score = 0
    if address and len(address.strip()) >= 3:
        if any(kw in address for kw in ["خیابان", "خ ", "کوچه", "پلاک", "منزل", "روستا", "شهرک", "بلوار", "میدان"]):
            address_score = 15  # استان/شهر + جزئیات
        elif len(address.strip()) >= 5:
            address_score = 10  # فقط شهر یا منطقه
        else:
            address_score = 5
    else:
        address_score = 0

    # ۴. اقلام — ۳۰ امتیاز
    items_score = 0
    if order_item and len(order_item.strip()) >= 2:
        if any(kw in order_item for kw in ["عدد", "دستگاه", "دست"]):
            items_score = 30  # نام کالا دقیق + تعداد
        else:
            items_score = 15  # کالا پیدا شده بدون تعداد
    else:
        items_score = 0

    # ۵. فیش — ۱۵ امتیاز
    payment_score = 0
    if "واریزی چک شد" in raw_text and not tracking_number and not (amount_num and amount_num > 0):
        payment_score = 0  # صرفاً جمله «واریزی چک شد» مدرک واریز نیست
    elif tracking_number or (amount_num and amount_num > 0) or bank_name:
        payment_score = 15
    else:
        payment_score = 0

    score = name_score + phone_score + address_score + items_score + payment_score

    # بررسی گیت‌های اجباری
    has_hard_gates = bool(name_score >= 15 and phone_score >= 15 and address_score >= 10 and items_score >= 15 and payment_score >= 15)

    missing_list = []
    if name_score < 15: missing_list.append("نام و نام خانوادگی")
    if phone_score < 15: missing_list.append("شماره تماس")
    if address_score < 10: missing_list.append("آدرس دقیق")
    if items_score < 15: missing_list.append("اقلام و تعداد سفارش")
    if payment_score < 15: missing_list.append("تصویر یا شماره پیگیری فیش واریزی")

    missing_params = " ، ".join(missing_list) if missing_list else ""
    missing_count = len(missing_list)

    auto_reply_sent = False
    if score >= 90 and has_hard_gates:
        status = "completed"
        reply_text = ""
    elif score >= 80:
        # ارسال/تولید درجا ریپلای خودکار کانال برای امتیاز بالای ۸۰ تا ۹۰
        status = "pending"
        auto_reply_sent = True
        if missing_count == 1:
            reply_text = f"سفارش شما دریافت شد ✅\nبرای ثبت فاکتور فقط {missing_list[0]} شما ارسال نشده است.\nلطفاً {missing_list[0]} را ارسال فرمایید. 🌹"
        elif missing_count == 2:
            reply_text = f"سفارش شما دریافت شد ✅\nبرای ثبت فاکتور، لطفاً موارد زیر را ارسال فرمایید:\n▫️ {missing_list[0]}\n▫️ {missing_list[1]}\nبا تشکر 🌹"
        else:
            reply_text = f"سفارش شما دریافت شد ✅\nجهت ثبت فاکتور لطفاً موارد زیر را ارسال فرمایید:\n" + "\n".join([f"▫️ {m}" for m in missing_list]) + "\nبا تشکر 🌹"
        print(f"🤖 [Auto-Reply Channel Trigger] Instant reply generated for Message #{msg_id} (Score: {score}):\n{reply_text}")
    else:
        status = "pending"
        reply_text = ""

    return {
        "msg_id": msg_id,
        "category": category,
        "type": category,
        "bank_name": bank_name or "",
        "amount": amount_num or 0,
        "tracking_number": tracking_number or "",
        "sender": customer_name,
        "receiver": data.get("receiver", ""),
        "destination_iban": data.get("destination_iban", ""),
        "date_str": date_str or "",
        "phones": phones_str,
        "customer_name": customer_name,
        "address": address,
        "order_item": order_item,
        "raw_text": raw_text,
        "discount_amount": calculated_discount,
        "score": score,
        "status": status,
        "missing_params": missing_params,
        "reply_text": reply_text
    }

def parse_rubika_html(html_content):
    matches = re.findall(r'data-msg-id="(\d+)".*?<div class="message">(.*?)(?:<div class="reactions"|</div></div>)', html_content, re.DOTALL)
    saved_count = 0
    records = []

    for msg_id, msg_inner in matches:
        clean_text = re.sub(r'<br\s*/?>', '\n', msg_inner)
        clean_text = re.sub(r'<[^>]+>', '', clean_text)
        clean_text = re.sub(r'\n+', '\n', clean_text).strip()

        if not clean_text:
            continue

        parsed = categorize_and_parse({"msg_id": msg_id, "raw_text": clean_text})
        if parsed:
            record_id = save_receipt(parsed)
            if record_id:
                saved_count += 1
                records.append({"id": record_id, "msg_id": msg_id, "parsed": parsed})

    # خروجی گرفتن برای فایل takhfif_module_export.json
    get_takhfif_module_export()

    return {"saved_count": saved_count, "records": records}

def get_takhfif_module_export():
    records = get_all_receipts()
    export_list = []

    for r in records:
        raw_text = r.get("raw_text", "")
        msg_id = str(r.get("msg_id", ""))

        if any(ign in raw_text for ign in ["یک سفارش از بالامونده", "یک سفارش از بالا مونده"]) and not r.get("tracking_number"):
            continue

        cat = r.get("category", "")
        rec_type = "bank_receipt" if cat == "bank_receipt" or r.get("bank_name") or r.get("tracking_number") else "customer_order"

        cust_name = r.get("customer_name") or r.get("sender") or ""
        phones = r.get("phones") or ""
        address = r.get("address") or ""
        order_item = r.get("order_item") or ""

        item_dict = {
            "msg_id": msg_id,
            "customer_name": cust_name,
            "phones": phones,
            "address": address,
            "order_item": order_item,
            "tracking_number": str(r.get("tracking_number") or ""),
            "amount": int(r.get("amount") or 0),
            "bank_name": str(r.get("bank_name") or ""),
            "date": str(r.get("date_str") or ""),
            "discount_amount": int(r.get("discount_amount") or 0),
            "type": rec_type,
            "score": int(r.get("score") or 0),
            "status": str(r.get("status") or "pending"),
            "missing_params": str(r.get("missing_params") or ""),
            "reply_text": str(r.get("reply_text") or "")
        }
        export_list.append(item_dict)

    export_list = export_list[::-1]

    try:
        with open(EXPORT_JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(export_list, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print("❌ Error writing takhfif_module_export.json:", e)

    return export_list

def save_receipt(parsed_data):
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()

    if parsed_data.get("tracking_number"):
        cursor.execute("SELECT id FROM receipts WHERE tracking_number = ?", (parsed_data["tracking_number"],))
        if cursor.fetchone():
            conn.close()
            return None

    if parsed_data.get("msg_id"):
        cursor.execute("SELECT id FROM receipts WHERE msg_id = ?", (parsed_data["msg_id"],))
        if cursor.fetchone():
            conn.close()
            return None

    cursor.execute('''
        INSERT INTO receipts (
            msg_id, category, bank_name, amount, tracking_number,
            sender, receiver, destination_iban, date_str, phones,
            customer_name, address, order_item, raw_text, discount_amount,
            score, status, missing_params, reply_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        parsed_data["msg_id"], parsed_data["category"], parsed_data["bank_name"],
        parsed_data["amount"], parsed_data["tracking_number"], parsed_data["sender"],
        parsed_data["receiver"], parsed_data["destination_iban"], parsed_data["date_str"],
        parsed_data["phones"], parsed_data["customer_name"], parsed_data["address"],
        parsed_data.get("order_item", ""), parsed_data["raw_text"], parsed_data["discount_amount"],
        parsed_data.get("score", 0), parsed_data.get("status", "pending"),
        parsed_data.get("missing_params", ""), parsed_data.get("reply_text", "")
    ))
    conn.commit()
    inserted_id = cursor.lastrowid
    conn.close()
    return inserted_id

def get_all_receipts(limit=None, before_id=None):
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = "SELECT * FROM receipts"
    params = []
    if before_id:
        query += " WHERE id < ?"
        params.append(before_id)
    query += " ORDER BY id DESC"
    if limit:
        query += " LIMIT ?"
        params.append(limit)
    cursor.execute(query, params)
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows

def get_auto_responses():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM auto_responses WHERE is_active = 1 ORDER BY id DESC")
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows

def add_auto_response(keyword, response_text, match_type='contains'):
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    try:
        cursor.execute('''
            INSERT OR REPLACE INTO auto_responses (keyword, response_text, match_type, is_active)
            VALUES (?, ?, ?, 1)
        ''', (keyword.strip(), response_text.strip(), match_type))
        conn.commit()
        last_id = cursor.lastrowid
        conn.close()
        return last_id
    except Exception as e:
        conn.close()
        raise e

def delete_auto_response(rule_id):
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM auto_responses WHERE id = ?", (rule_id,))
    conn.commit()
    conn.close()

class ReceiptHandler(http.server.BaseHTTPRequestHandler):
    def _set_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(200, "ok")
        self._set_cors_headers()
        self.end_headers()

    def do_GET(self):
        try:
            parsed_url = urlparse(self.path)
            if parsed_url.path == '/api/receipts':
                query_params = parse_qs(parsed_url.query)
                limit = int(query_params.get('limit', [0])[0]) if query_params.get('limit') else None
                before_id = int(query_params.get('before_id', [0])[0]) if query_params.get('before_id') else None

                receipts = get_all_receipts(limit=limit, before_id=before_id)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": receipts}, ensure_ascii=False).encode('utf-8'))

            elif parsed_url.path == '/api/auto-responses':
                rules = get_auto_responses()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": rules}, ensure_ascii=False).encode('utf-8'))

            elif parsed_url.path == '/api/smm/balance':
                res = get_rubika1_balance()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": res}, ensure_ascii=False).encode('utf-8'))

            elif parsed_url.path == '/api/smm/services':
                res = get_rubika1_services()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": res}, ensure_ascii=False).encode('utf-8'))

            elif parsed_url.path == '/api/smm/status':
                query_params = parse_qs(parsed_url.query)
                order_id = query_params.get('order', [''])[0]
                res = get_rubika1_order_status(order_id)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": res}, ensure_ascii=False).encode('utf-8'))

            elif parsed_url.path == '/api/takhfif_module':
                export_data = get_takhfif_module_export()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps(export_data, ensure_ascii=False, indent=2).encode('utf-8'))
            else:
                self.send_response(404)
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": "Not found"}).encode('utf-8'))
        except Exception as e:
            print(f"❌ خطا در پردازش درخواست GET ({self.path}):", e)
            try:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode('utf-8'))
            except Exception:
                pass

    def do_POST(self):
        parsed_url = urlparse(self.path)
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        if parsed_url.path == '/api/receipts':
            try:
                data = json.loads(post_data.decode('utf-8'))
                parsed = categorize_and_parse(data)
                record_id = save_receipt(parsed)

                response_data = {
                    "success": True,
                    "message": "صورتحساب ثبت شد" if record_id else "صورتحساب تکراری بود",
                    "id": record_id,
                    "parsed": parsed
                }
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps(response_data, ensure_ascii=False).encode('utf-8'))

            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode('utf-8'))

        elif parsed_url.path == '/api/auto-responses':
            try:
                data = json.loads(post_data.decode('utf-8'))
                rule_id = add_auto_response(data.get("keyword"), data.get("response_text"), data.get("match_type", "contains"))

                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "id": rule_id}, ensure_ascii=False).encode('utf-8'))
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode('utf-8'))

        elif parsed_url.path == '/api/import-html':
            try:
                body_str = post_data.decode('utf-8')
                try:
                    json_body = json.loads(body_str)
                    html_content = json_body.get('html', body_str)
                except Exception:
                    html_content = body_str

                res = parse_rubika_html(html_content)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": res}, ensure_ascii=False).encode('utf-8'))
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode('utf-8'))

        elif parsed_url.path == '/api/takhfif_module':
            try:
                body_str = post_data.decode('utf-8')
                try:
                    json_body = json.loads(body_str)
                    if isinstance(json_body, list):
                        for item in json_body:
                            if isinstance(item, dict):
                                raw = item.get("raw_text") or json.dumps(item, ensure_ascii=False)
                                parsed = categorize_and_parse({"msg_id": item.get("msg_id", ""), "raw_text": raw, **item})
                                if parsed:
                                    save_receipt(parsed)
                    elif isinstance(json_body, dict):
                        html_content = json_body.get('html')
                        if html_content:
                            parse_rubika_html(html_content)
                        else:
                            raw = json_body.get("raw_text") or json.dumps(json_body, ensure_ascii=False)
                            parsed = categorize_and_parse({"msg_id": json_body.get("msg_id", ""), "raw_text": raw, **json_body})
                            if parsed:
                                save_receipt(parsed)
                except Exception:
                    parse_rubika_html(body_str)

                export_data = get_takhfif_module_export()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps(export_data, ensure_ascii=False, indent=2).encode('utf-8'))
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode('utf-8'))

    def do_DELETE(self):
        parsed_url = urlparse(self.path)
        if parsed_url.path.startswith('/api/auto-responses/'):
            try:
                rule_id = int(parsed_url.path.split('/')[-1])
                delete_auto_response(rule_id)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True}).encode('utf-8'))
            except Exception as e:
                self.send_response(400)
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode('utf-8'))

if __name__ == "__main__":
    init_db()
    print(f"🚀 سرور ماژول تخفیف و پنل Rubika1 روی پورت {PORT} فعال شد...")
    print(f"🔑 کلید API ثبت شده: {RUBIKA1_API_KEY[:6]}...")

    with socketserver.TCPServer(("", PORT), ReceiptHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n🛑 سرور متوقف شد.")
