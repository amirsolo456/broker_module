import asyncio
import os
from typing import Any

import requests
from playwright.async_api import async_playwright, Page


TARGET_CHAT_ID = os.getenv(
    "RUBIKA_TARGET_CHAT_ID",
    os.getenv(
        "RUBIKA_TARGET_GROUP_ID",
        "g0HUhDZ03024bd85fad3e51ae86e52e8",
    ),
).strip()

TARGET_CHAT_URL = os.getenv(
    "RUBIKA_TARGET_CHAT_URL",
    f"https://web.rubika.ir/#c={TARGET_CHAT_ID}",
).strip()

SERVER_BASE = os.getenv(
    "BROKER_SERVER_BASE",
    "http://127.0.0.1:5050",
).rstrip("/")

API_RECEIPTS = f"{SERVER_BASE}/api/receipts"
API_RULES = f"{SERVER_BASE}/api/auto-responses"
API_CLAIM_REPLY = f"{SERVER_BASE}/api/auto-reply/claim"

USER_DATA_DIR = os.getenv(
    "RUBIKA_USER_DATA_DIR",
    "./rubika_user_session",
)

SCAN_INTERVAL_SECONDS = float(
    os.getenv("RUBIKA_SCAN_INTERVAL", "2.0")
)

HISTORY_SCROLL_EVERY = max(
    1,
    int(os.getenv("RUBIKA_HISTORY_SCROLL_EVERY", "8")),
)

HISTORY_SCROLL_WAIT_MS = max(
    100,
    int(os.getenv("RUBIKA_HISTORY_SCROLL_WAIT_MS", "1200")),
)

RULE_REFRESH_EVERY = max(
    1,
    int(os.getenv("RUBIKA_RULE_REFRESH_EVERY", "15")),
)


processed_messages: set[str] = set()
auto_rules: list[dict[str, Any]] = []


def fetch_auto_rules() -> None:
    global auto_rules

    try:
        response = requests.get(API_RULES, timeout=5)
        response.raise_for_status()

        payload = response.json()
        if payload.get("success"):
            auto_rules = payload.get("data", []) or []
            print(f"🔄 قوانین پاسخگو: {len(auto_rules)}")
    except Exception as exc:
        print(f"⚠️ دریافت قوانین پاسخگو ناموفق بود: {exc}")


def send_to_broker(msg_id: str, text: str) -> bool:
    try:
        response = requests.post(
            API_RECEIPTS,
            json={
                "msg_id": msg_id,
                "chat_id": TARGET_CHAT_ID,
                "source_chat_id": TARGET_CHAT_ID,
                "raw_text": text,
            },
            timeout=5,
        )
        response.raise_for_status()

        payload = response.json()
        print(
            f"📥 پیام {msg_id} → "
            f"{payload.get('message', 'ثبت شد')}"
        )
        return bool(payload.get("success"))
    except Exception as exc:
        print(f"❌ ارسال پیام {msg_id} به Broker ناموفق بود: {exc}")
        return False


def claim_auto_reply(msg_id: str, rule_id: int) -> bool:
    try:
        response = requests.post(
            API_CLAIM_REPLY,
            json={"msg_id": msg_id, "rule_id": rule_id},
            timeout=5,
        )
        response.raise_for_status()

        payload = response.json()
        return bool(
            payload.get("success")
            and payload.get("claimed")
        )
    except Exception as exc:
        print(f"⚠️ Claim پاسخ خودکار ناموفق بود: {exc}")
        return False


async def target_chat_present(page: Page) -> bool:
    return (
        await page.query_selector(
            f'[data-chat-id="{TARGET_CHAT_ID}"]'
        )
    ) is not None


async def scroll_target_history(page: Page) -> bool:
    """گروه هدف را فقط به سمت پیام‌های قدیمی‌تر اسکرول می‌کند."""
    try:
        result = await page.evaluate(
            """
            (targetId) => {
                const root = document.querySelector(
                    '[data-chat-id="' + targetId + '"]'
                );

                if (!root) {
                    return { ok: false, moved: false };
                }

                const all = [root, ...root.querySelectorAll('*')];

                const candidates = all.filter((el) => {
                    const style = getComputedStyle(el);
                    return (
                        el.scrollHeight > el.clientHeight + 80 &&
                        (
                            style.overflowY === 'auto' ||
                            style.overflowY === 'scroll' ||
                            el === root
                        )
                    );
                });

                if (!candidates.length) {
                    return { ok: true, moved: false };
                }

                candidates.sort(
                    (a, b) =>
                        (b.scrollHeight - b.clientHeight) -
                        (a.scrollHeight - a.clientHeight)
                );

                const scroller = candidates[0];
                const before = scroller.scrollTop;

                scroller.scrollTop = 0;
                scroller.dispatchEvent(
                    new Event('scroll', { bubbles: true })
                );

                return {
                    ok: true,
                    moved: Math.abs(before - scroller.scrollTop) > 1,
                    before,
                    after: scroller.scrollTop,
                };
            }
            """,
            TARGET_CHAT_ID,
        )

        if result.get("moved"):
            await page.wait_for_timeout(HISTORY_SCROLL_WAIT_MS)

        return bool(result.get("ok"))
    except Exception as exc:
        print(f"⚠️ خطا در خزش تاریخچه: {exc}")
        return False


async def collect_target_messages(page: Page) -> list[dict[str, str]]:
    """فقط پیام‌های داخل چت هدف را با msg_id یکتا استخراج می‌کند."""
    messages = await page.evaluate(
        """
        (targetId) => {
            const root = document.querySelector(
                '[data-chat-id="' + targetId + '"]'
            );

            if (!root) {
                return [];
            }

            const seen = new Set();
            const result = [];

            for (const el of root.querySelectorAll('[data-msg-id]')) {
                const msgId = (el.getAttribute('data-msg-id') || '').trim();

                if (!msgId || seen.has(msgId)) {
                    continue;
                }

                seen.add(msgId);

                result.push({
                    msgId,
                    text: (el.innerText || el.textContent || '').trim(),
                    classes: (
                        el.getAttribute('class') || ''
                    ).toLowerCase(),
                });
            }

            return result;
        }
        """,
        TARGET_CHAT_ID,
    )

    return messages


async def find_message_input(page: Page):
    selectors = [
        'div[contenteditable="true"]',
        ".input-message-input",
        ".textbox-field-input",
    ]

    for selector in selectors:
        element = await page.query_selector(selector)
        if element:
            return element

    return None


async def send_auto_reply(page: Page, reply_text: str) -> bool:
    if not reply_text.strip():
        return False

    try:
        if not await target_chat_present(page):
            print("⚠️ چت هدف فعال نیست؛ پاسخ خودکار ارسال نشد.")
            return False

        input_el = await find_message_input(page)
        if not input_el:
            print("⚠️ کادر ارسال پیام روبیکا پیدا نشد.")
            return False

        await input_el.click()
        await input_el.fill(reply_text)
        await page.keyboard.press("Enter")

        print("✅ پاسخ خودکار ارسال شد.")
        return True
    except Exception as exc:
        print(f"⚠️ خطا در ارسال پاسخ خودکار: {exc}")
        return False


async def process_messages(
    page: Page,
    messages: list[dict[str, str]],
) -> None:
    for message in messages:
        msg_id = message.get("msgId", "").strip()
        text = message.get("text", "").strip()
        classes = message.get("classes", "").lower()

        if not msg_id or msg_id in processed_messages:
            continue

        if "service" in classes or not text:
            processed_messages.add(msg_id)
            continue

        # پیام‌های ارسال‌شده توسط خود مرورگر/اکانت را دوباره پردازش نکن.
        if "is-sent" in classes:
            processed_messages.add(msg_id)
            continue

        if not send_to_broker(msg_id, text):
            # در صورت خطای شبکه، در دور بعد دوباره تلاش می‌شود.
            continue

        processed_messages.add(msg_id)

        for rule in auto_rules:
            keyword = str(rule.get("keyword") or "").strip()
            rule_id = int(rule.get("id") or 0)
            response_text = str(
                rule.get("response_text") or ""
            ).strip()

            if (
                not keyword
                or rule_id <= 0
                or keyword not in text
                or not response_text
            ):
                continue

            if claim_auto_reply(msg_id, rule_id):
                await send_auto_reply(
                    page,
                    response_text,
                )

            break


async def main() -> None:
    if not TARGET_CHAT_ID:
        raise RuntimeError(
            "RUBIKA_TARGET_CHAT_ID تنظیم نشده است."
        )

    fetch_auto_rules()

    async with async_playwright() as playwright:
        context = await playwright.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            headless=False,
            args=[
                "--no-sandbox",
                "--disable-setuid-sandbox",
            ],
        )

        page = (
            context.pages[0]
            if context.pages
            else await context.new_page()
        )

        print(
            "🌐 باز کردن چت هدف روبیکا:"
            f" {TARGET_CHAT_URL}"
        )

        await page.goto(
            TARGET_CHAT_URL,
            wait_until="domcontentloaded",
        )

        await page.wait_for_timeout(5000)

        loop_counter = 0
        warned_not_found = False

        while True:
            loop_counter += 1

            if (
                loop_counter % RULE_REFRESH_EVERY == 0
            ):
                fetch_auto_rules()

            try:
                if not await target_chat_present(page):
                    if not warned_not_found:
                        print(
                            "⚠️ چت هدف در DOM پیدا نشد؛ "
                            "منتظر لود روبیکا هستیم..."
                        )
                        warned_not_found = True

                    await asyncio.sleep(3)
                    continue

                warned_not_found = False

                if (
                    loop_counter
                    % HISTORY_SCROLL_EVERY
                    == 0
                ):
                    await scroll_target_history(page)

                messages = await collect_target_messages(page)

                if messages:
                    await process_messages(
                        page,
                        messages,
                    )

            except Exception as exc:
                print(
                    f"⚠️ خطا در پایش چت هدف: {exc}"
                )

            await asyncio.sleep(
                SCAN_INTERVAL_SECONDS
            )


if __name__ == "__main__":
    asyncio.run(main())
