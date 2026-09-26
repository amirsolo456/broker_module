import asyncio
import re
import json
import requests
from playwright.async_api import async_playwright

# -------------------------------------------------------------------
# تنظیمات ربات و پاسخگوی هوشمند
# -------------------------------------------------------------------
RUBIKA_URL = "https://web.rubika.ir/#c=g0HUhDZ03024bd85fad3e51ae86e52e8"
SERVER_BASE = "http://localhost:5000"
API_RECEIPTS = f"{SERVER_BASE}/api/receipts"
API_RULES = f"{SERVER_BASE}/api/auto-responses"
USER_DATA_DIR = "./rubika_user_session"

processed_messages = set()
auto_rules = []

def fetch_auto_rules():
    """دریافت آخرین قوانین پاسخگوی هوشمند از سرور"""
    global auto_rules
    try:
        res = requests.get(API_RULES, timeout=5)
        if res.status_code == 200:
            data = res.json()
            if data.get("success"):
                auto_rules = data.get("data", [])
                print(f"🔄 قوانین پاسخگوی هوشمند به‌روزرسانی شد: {len(auto_rules)} قانون فعال")
    except Exception as e:
        print("⚠️ خطا در دریافت قوانین پاسخگوی هوشمند:", e)

def parse_receipt_text(text: str) -> dict:
    """استخراج و طبقه‌بندی اطلاعات صورتحساب"""
    clean_text = text.strip()

    parsed = {
        "raw_text": clean_text,
        "bank_name": None,
        "amount": None,
        "tracking_number": None,
        "sender": None,
        "receiver": None,
        "destination_iban": None,
        "date": None,
        "phones": []
    }

    bank_match = re.search(r'(بانک\s+[\u0600-\u06FF]+|بلوبانک|بانکت)', clean_text)
    if bank_match:
        parsed["bank_name"] = bank_match.group(0)

    amount_match = re.search(r'مبلغ[:\s]*([\d,۰-۹]+)\s*(ریال|تومان)?', clean_text)
    if amount_match:
        parsed["amount"] = amount_match.group(1).replace(',', '').replace('،', '')

    track_match = re.search(r'(?:شماره|کد)\s*پیگیری[:\s]*([\d۰-۹]+)', clean_text)
    if track_match:
        parsed["tracking_number"] = track_match.group(1)

    phones = re.findall(r'(?:09|۰۹)[\d۰-۹]{9}', clean_text)
    if phones:
        parsed["phones"] = list(set(phones))

    return parsed

def send_to_discount_module(payload: dict):
    """ارسال اطلاعات صورتحساب به سرور ماژول تخفیف"""
    try:
        res = requests.post(API_RECEIPTS, json=payload, timeout=5)
        print("✅ صورتحساب به سرور ارسال شد:", res.json().get("message"))
    except Exception as e:
        print("❌ خطا در ارسال صورتحساب:", e)

async def send_auto_reply(page, reply_text):
    """ارسال پاسخ خودکار در چت روبیکا توسط Playwright"""
    try:
        print(f"💬 در حال ارسال پاسخ خودکار: {reply_text}")

        # پیدا کردن کادر ورودی پیام
        input_selector = 'div[contenteditable="true"], .input-message-input, .textbox-field-input'
        await page.wait_for_selector(input_selector, timeout=3000)

        input_el = await page.query_selector(input_selector)
        if input_el:
            await input_el.focus()
            await input_el.fill(reply_text)
            await page.keyboard.press('Enter')
            print("✅ پاسخ خودکار ارسال شد.")
    except Exception as e:
        print("⚠️ خطا در ارسال پاسخ خودکار:", e)

async def main():
    fetch_auto_rules()

    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            headless=False,
            args=["--no-sandbox", "--disable-setuid-sandbox"]
        )

        page = await context.new_page()
        print(f"🌐 در حال باز کردن روبیکا وب: {RUBIKA_URL}")
        await page.goto(RUBIKA_URL)
        await page.wait_for_timeout(5000)

        loop_counter = 0
        while True:
            loop_counter += 1
            if loop_counter % 10 == 0:
                fetch_auto_rules() # بروزرسانی قوانین هر ۳۰ ثانیه

            try:
                elements = await page.query_selector_all('div[rb-copyable], div[style*="unicode-bidi"]')

                for el in elements:
                    text = await el.inner_text()
                    text = text.strip()

                    if text and text not in processed_messages:
                        processed_messages.add(text)

                        # ۱. بررسی و ثبت صورتحساب
                        if any(kw in text for kw in ["رسید", "مبلغ", "پیگیری", "بانک"]):
                            parsed_data = parse_receipt_text(text)
                            send_to_discount_module(parsed_data)

                        # ۲. بررسی کلمات کلیدی پاسخگوی هوشمند
                        for rule in auto_rules:
                            keyword = rule.get("keyword", "").strip()
                            if keyword and keyword in text:
                                print(f"🎯 تطابق کلمه کلیدی: '{keyword}'")
                                await send_auto_reply(page, rule.get("response_text", ""))
                                break

            except Exception as e:
                print("⚠️ خطا در پایش صفحه:", e)

            await asyncio.sleep(3)

if __name__ == "__main__":
    asyncio.run(main())
