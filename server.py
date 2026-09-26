import http.server
import socketserver
import json
import sqlite3
import re
import urllib.request
import urllib.parse
import os
from datetime import datetime
from urllib.parse import parse_qs, urlparse

PORT = int(os.getenv("BROKER_PORT", "5050"))
DB_NAME = os.getenv("BROKER_DB_NAME", "live_receipts.db")
RUBIKA1_API_KEY = os.getenv("RUBIKA1_API_KEY", "").strip()
RUBIKA1_API_URL = "https://rubika1.ir/api/v1"
TARGET_GROUP_ID = os.getenv("RUBIKA_TARGET_GROUP_ID", "g0HUhDZ03024bd85fad3e51ae86e52e8")

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

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS auto_reply_claims (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            msg_id TEXT NOT NULL,
            rule_id INTEGER NOT NULL,
            claimed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(msg_id, rule_id)
        )
    ''')

    # هیچ قانون پاسخ خودکار یا اطلاعات کسب‌وکار به‌صورت ثابت در سورس Seed نمی‌شود.
    # قوانین فقط از طریق API /api/auto-responses و پنل مدیریت ثبت می‌شوند.

    conn.commit()
    conn.close()

# -------------------------------------------------------------------
# توابع مربوط به API پنل rubika1.ir
# -------------------------------------------------------------------
def rubika1_request(payload):
    if not RUBIKA1_API_KEY:
        return {"status": "error", "message": "RUBIKA1_API_KEY تنظیم نشده است."}
    try:
        payload = dict(payload)
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

# -------------------------------------------------------------------
# پارسر صورتحساب و پیام‌های روبیکا طبق قوانین takhfif_module
# -------------------------------------------------------------------
def to_int(value):
    if value is None or value == "":
        return 0
    try:
        if isinstance(value, str):
            value = value.translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789"))
            value = value.replace(",", "").replace("٬", "").replace("،", "").strip()
        return int(value)
    except (TypeError, ValueError):
        return 0

def is_relevant_message(raw_text):
    bank_keywords = [
        "رسید", "بانک", "مبلغ", "پیگیری", "حساب", "شبا",
        "پایا", "کارت به کارت", "سپینو", "بام", "انتقال یافت"
    ]
    order_keywords = [
        "سفارش", "عدد", "دستگاه", "پشم چین", "پشمچین",
        "آبخوری", "سرنگ", "پلاک گردنی", "قیچی", "سم چین",
        "ماشین", "فاکتور"
    ]
    return any(k in raw_text for k in bank_keywords + order_keywords)

def categorize_and_parse(data):
    raw_text = data.get("raw_text", "").strip()
    msg_id = str(data.get("msg_id", ""))

    if not raw_text or not is_relevant_message(raw_text):
        return None

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
    amount_num = to_int(data.get("amount"))
    if not amount_num:
        amt_match = re.search(r'مبلغ\s*[:؛]?\s*([0-9,]+)', normalized_text)
        if amt_match:
            try:
                amount_num = int(re.sub(r'\D', '', amt_match.group(1)))
            except:
                amount_num = 0

    # استخراج شماره پیگیری
    tracking_number = str(data.get("tracking_number") or "").translate(trans)
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
    else:
        # برای تمام پیام‌های با امتیاز زیر ۱۰۰ (دارای نقص پارامتر)، ریپلای اختصاصی درجا تولید و صادر می‌شود
        status = "pending"
        auto_reply_sent = True
        if missing_count == 1:
            reply_text = f"سفارش شما دریافت شد ✅\nبرای ثبت فاکتور فقط {missing_list[0]} شما ارسال نشده است.\nلطفاً {missing_list[0]} را ارسال فرمایید. 🌹"
        elif missing_count == 2:
            reply_text = f"سفارش شما دریافت شد ✅\nبرای ثبت فاکتور، لطفاً موارد زیر را ارسال فرمایید:\n▫️ {missing_list[0]}\n▫️ {missing_list[1]}\nبا تشکر 🌹"
        else:
            reply_text = f"سفارش شما دریافت شد ✅\nجهت ثبت فاکتور لطفاً موارد زیر را ارسال فرمایید:\n" + "\n".join([f"▫️ {m}" for m in missing_list]) + "\nبا تشکر 🌹"
        print(f"🤖 [Auto-Reply Channel Trigger] Instant reply generated for Message #{msg_id} (Score: {score}):\n{reply_text}")

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

            elif parsed_url.path == '/api/smm/order':
                self.send_response(405)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": "برای ثبت سفارش از POST استفاده کنید."}, ensure_ascii=False).encode('utf-8'))

            elif parsed_url.path == '/api/smm/status':
                query_params = parse_qs(parsed_url.query)
                order_id = query_params.get('order', [''])[0]
                res = get_rubika1_order_status(order_id)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "data": res}, ensure_ascii=False).encode('utf-8'))

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
                source_chat_id = str(data.get("chat_id") or data.get("source_chat_id") or "").strip()
                if source_chat_id and source_chat_id != TARGET_GROUP_ID:
                    self.send_response(403)
                    self.send_header('Content-Type', 'application/json; charset=utf-8')
                    self._set_cors_headers()
                    self.end_headers()
                    self.wfile.write(json.dumps({"success": False, "error": "پیام متعلق به گروه هدف نیست."}, ensure_ascii=False).encode('utf-8'))
                    return

                parsed = categorize_and_parse(data)
                if parsed is None:
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json; charset=utf-8')
                    self._set_cors_headers()
                    self.end_headers()
                    self.wfile.write(json.dumps({"success": True, "message": "پیام نادیده گرفته شد", "id": None, "parsed": None}, ensure_ascii=False).encode('utf-8'))
                    return

                record_id = save_receipt(parsed)

                response_data = {
                    "success": True,
                    "message": "سفارش/رسید ثبت شد" if record_id else "پیام تکراری بود",
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

        elif parsed_url.path == '/api/smm/order':
            try:
                data = json.loads(post_data.decode('utf-8'))
                service_id = str(data.get("service") or "").strip()
                link = str(data.get("link") or "").strip()
                quantity = to_int(data.get("quantity"))
                comments = str(data.get("comments") or "").strip()
                if not service_id or not link or quantity <= 0:
                    raise ValueError("service، link و quantity الزامی هستند.")
                res = add_rubika1_order(service_id, link, quantity, comments)
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
                self.wfile.write(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False).encode('utf-8'))

        elif parsed_url.path == '/api/auto-reply/claim':
            try:
                data = json.loads(post_data.decode('utf-8'))
                msg_id = str(data.get("msg_id") or "").strip()
                rule_id = to_int(data.get("rule_id"))
                if not msg_id or rule_id <= 0:
                    raise ValueError("msg_id و rule_id الزامی هستند.")
                conn = sqlite3.connect(DB_NAME)
                cursor = conn.cursor()
                cursor.execute("INSERT OR IGNORE INTO auto_reply_claims (msg_id, rule_id) VALUES (?, ?)", (msg_id, rule_id))
                claimed = cursor.rowcount == 1
                conn.commit()
                conn.close()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "claimed": claimed}, ensure_ascii=False).encode('utf-8'))
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False).encode('utf-8'))

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
    print(f"🚀 سرور زنده Broker و پنل Rubika1 روی پورت {PORT} فعال شد...")
    print(f"🗄️ دیتابیس زنده: {DB_NAME}")
    print(f"🎯 گروه هدف روبیکا: {TARGET_GROUP_ID}")
    print(f"🔐 API Key: {'تنظیم شده' if RUBIKA1_API_KEY else 'تنظیم نشده'}")

    with socketserver.TCPServer(("", PORT), ReceiptHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n🛑 سرور متوقف شد.")
