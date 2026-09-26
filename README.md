# broker_module

ماژول مدیریت سفارش/رسید روبیکا و اتصال به rubika1.ir.

## سرور

سرور روی پورت `5050` اجرا می‌شود.

PowerShell:
```powershell
$env:RUBIKA1_API_KEY="YOUR_NEW_KEY"
$env:RUBIKA_TARGET_GROUP_ID="g0HUhDZ03024bd85fad3e51ae86e52e8"
python server.py
```

## ربات Playwright

```powershell
$env:BROKER_SERVER_BASE="http://localhost:5050"
$env:RUBIKA_TARGET_GROUP_ID="g0HUhDZ03024bd85fad3e51ae86e52e8"
python rubika_bot.py
```

ربات فقط کانتینر گروه هدف با `data-chat-id` مطابق را می‌خواند و تمام پیام‌های واقعی آن گروه را با `msg_id` برای سرور می‌فرستد.

## Tampermonkey

`rubika_collector.user.js` نیز فقط گروه هدف را اسکن می‌کند و به سرور `5050` وصل می‌شود.

در صورت اجرای همزمان دو collector، endpoint داخلی Claim از پاسخ خودکار تکراری جلوگیری می‌کند.

## امنیت

کلید قبلی rubika1.ir داخل سورس قرار داشت؛ آن کلید را باطل و کلید جدید را فقط از طریق environment variable تنظیم کنید.
