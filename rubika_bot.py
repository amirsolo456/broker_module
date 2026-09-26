import asyncio
import os
import requests
from playwright.async_api import async_playwright

TARGET_GROUP_ID = os.getenv("RUBIKA_TARGET_GROUP_ID", "g0HUhDZ03024bd85fad3e51ae86e52e8")
RUBIKA_URL = f"https://web.rubika.ir/#c={TARGET_GROUP_ID}"
SERVER_BASE = os.getenv("BROKER_SERVER_BASE", "http://localhost:5050").rstrip("/")
API_RECEIPTS = f"{SERVER_BASE}/api/receipts"
API_RULES = f"{SERVER_BASE}/api/auto-responses"
API_CLAIM_REPLY = f"{SERVER_BASE}/api/auto-reply/claim"
USER_DATA_DIR = os.getenv("RUBIKA_USER_DATA_DIR", "./rubika_user_session")

processed_messages = set()
auto_rules = []

def fetch_auto_rules():
    global auto_rules
    try:
        res = requests.get(API_RULES, timeout=5)
        res.raise_for_status()
        data = res.json()
        if data.get("success"):
            auto_rules = data.get("data", []) or []
            print(f"🔄 قوانین پاسخگو: {len(auto_rules)}")
    except Exception as e:
        print("⚠️ دریافت قوانین ناموفق:", e)

def send_to_discount_module(msg_id, text):
    try:
        res = requests.post(
            API_RECEIPTS,
            json={
                "msg_id": msg_id,
                "chat_id": TARGET_GROUP_ID,
                "raw_text": text,
            },
            timeout=5,
        )
        data = res.json()
        print(f"📥 پیام {msg_id} → {data.get('message', 'ثبت شد')}")
        return data
    except Exception as e:
        print("❌ ارسال پیام به سرور ناموفق:", e)
        return None

def claim_auto_reply(msg_id, rule_id):
    try:
        res = requests.post(
            API_CLAIM_REPLY,
            json={"msg_id": msg_id, "rule_id": rule_id},
            timeout=5,
        )
        data = res.json()
        return bool(data.get("success") and data.get("claimed"))
    except Exception as e:
        print("⚠️ Claim پاسخ ناموفق:", e)
        return False

async def send_auto_reply(page, reply_text):
    try:
        selectors = [
            'div[contenteditable="true"]',
            '.input-message-input',
            '.textbox-field-input',
        ]
        input_el = None
        for selector in selectors:
            input_el = await page.query_selector(selector)
            if input_el:
                break

        if not input_el:
            print("⚠️ کادر ارسال پیام پیدا نشد.")
            return False

        await input_el.click()
        await input_el.fill(reply_text)
        await page.keyboard.press("Enter")
        print("✅ پاسخ خودکار ارسال شد.")
        return True
    except Exception as e:
        print("⚠️ خطا در ارسال پاسخ:", e)
        return False

async def main():
    fetch_auto_rules()

    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            headless=False,
            args=["--no-sandbox", "--disable-setuid-sandbox"],
        )
        page = await context.new_page()
        print(f"🌐 باز کردن گروه هدف: {RUBIKA_URL}")
        await page.goto(RUBIKA_URL, wait_until="domcontentloaded")
        await page.wait_for_timeout(5000)

        loop_counter = 0
        warned_not_in_group = False

        while True:
            loop_counter += 1
            if loop_counter % 10 == 0:
                fetch_auto_rules()

            try:
                chat_root = await page.query_selector(f'[data-chat-id="{TARGET_GROUP_ID}"]')
                if not chat_root:
                    if not warned_not_in_group:
                        print("⚠️ کانتینر گروه هدف در DOM پیدا نشد؛ منتظر لود روبیکا...")
                        warned_not_in_group = True
                    await asyncio.sleep(3)
                    continue

                warned_not_in_group = False
                groups = await chat_root.query_selector_all("[data-msg-id]")

                for group in groups:
                    msg_id = await group.get_attribute("data-msg-id")
                    if not msg_id or msg_id in processed_messages:
                        continue

                    classes = (await group.get_attribute("class") or "").lower()
                    if "service" in classes:
                        processed_messages.add(msg_id)
                        continue

                    text = (await group.inner_text()).strip()
                    if not text:
                        processed_messages.add(msg_id)
                        continue

                    result = send_to_discount_module(msg_id, text)
                    if result is None:
                        continue

                    processed_messages.add(msg_id)

                    is_outgoing = "is-sent" in classes
                    if is_outgoing:
                        continue

                    for rule in auto_rules:
                        keyword = str(rule.get("keyword") or "").strip()
                        rule_id = int(rule.get("id") or 0)
                        if not keyword or not rule_id or keyword not in text:
                            continue

                        if claim_auto_reply(msg_id, rule_id):
                            await send_auto_reply(page, str(rule.get("response_text") or ""))
                        break

            except Exception as e:
                print("⚠️ خطا در پایش گروه:", e)

            await asyncio.sleep(3)

if __name__ == "__main__":
    asyncio.run(main())
