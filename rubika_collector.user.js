// ==UserScript==
// @name         Rubika Receipt Extractor & Smart Auto-Responder
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  استخراج خودکار صورتحساب‌ها و پاسخگوی هوشمند خودکار روبیکا
// @match        https://web.rubika.ir/*
// @grant        GM_xmlhttpRequest
// ==/UserScript==

(function() {
    'use strict';

    // -------------------------------------------------------------
    // تنظیمات آدرس سرور
    // -------------------------------------------------------------
    const SERVER_BASE = "http://localhost:5000";
    const API_RECEIPTS = `${SERVER_BASE}/api/receipts`;
    const API_RULES = `${SERVER_BASE}/api/auto-responses`;
    const TARGET_CHANNEL_ID = "g0HUhDZ03024bd85fad3e51ae86e52e8";

    const processedMsgKeys = new Set();
    let autoRules = [];

    // -------------------------------------------------------------
    // ایجاد پنل شناور وضعیت روی صفحه روبیکا
    // -------------------------------------------------------------
    const statusBox = document.createElement('div');
    statusBox.style.cssText = `
        position: fixed;
        bottom: 20px;
        left: 20px;
        z-index: 99999;
        background: #1e1e2e;
        color: #cdd6f4;
        padding: 12px 16px;
        border-radius: 10px;
        box-shadow: 0 4px 15px rgba(0,0,0,0.3);
        font-family: Tahoma, Vazir, sans-serif;
        font-size: 12px;
        direction: rtl;
        border: 1px solid #45475a;
    `;
    statusBox.innerHTML = `
        <div style="font-weight: bold; margin-bottom: 5px; color: #89b4fa;">🤖 ربات روبیکا (صورتحساب + پاسخگو)</div>
        <div id="rb-bot-status">در حال بارگذاری قوانین...</div>
        <div id="rb-bot-count" style="font-size: 11px; color: #a6adc8; margin-top: 4px;">صورتحساب: 0 | پاسخ خودکار: 0</div>
    `;
    document.body.appendChild(statusBox);

    let extractedCount = 0;
    let repliedCount = 0;

    function updateStatusUI(statusText) {
        const statusEl = document.getElementById('rb-bot-status');
        const countEl = document.getElementById('rb-bot-count');
        if (statusEl) statusEl.innerText = statusText;
        if (countEl) countEl.innerText = `صورتحساب: ${extractedCount} | پاسخ خودکار: ${repliedCount}`;
    }

    // -------------------------------------------------------------
    // دریافت قوانین پاسخگوی هوشمند از سرور
    // -------------------------------------------------------------
    function fetchAutoRules() {
        if (typeof GM_xmlhttpRequest !== "undefined") {
            GM_xmlhttpRequest({
                method: "GET",
                url: API_RULES,
                onload: function(res) {
                    try {
                        const json = JSON.parse(res.responseText);
                        if (json.success) {
                            autoRules = json.data || [];
                            updateStatusUI(`تعداد ${autoRules.length} قانون پاسخگوی هوشمند فعال شد.`);
                        }
                    } catch(e) {}
                }
            });
        }
    }

    // -------------------------------------------------------------
    // ارسال پیام پاسخ خودکار در وب روبیکا
    // -------------------------------------------------------------
    function sendAutoReplyInRubika(replyText) {
        console.log("💬 در حال ارسال پاسخ خودکار:", replyText);

        // پیدا کردن کادر ورودی پیام در روبیکا وب
        const inputEl = document.querySelector('div[contenteditable="true"]') ||
                        document.querySelector('.input-message-input') ||
                        document.querySelector('.textbox-field-input');

        if (!inputEl) {
            console.warn("⚠️ کادر ارسال پیام در روبیکا یافت نشد.");
            return;
        }

        // درج متن پاسخ در کادر ورودی
        inputEl.focus();
        inputEl.innerText = replyText;
        inputEl.dispatchEvent(new Event('input', { bubbles: true }));

        // ارسال پیام پس از ۵۰۰ میلی‌ثانیه
        setTimeout(() => {
            const sendBtn = document.querySelector('.btn-send') ||
                            document.querySelector('.send-button') ||
                            document.querySelector('i.icon-send') ||
                            document.querySelector('[rb-send-button]');

            if (sendBtn) {
                sendBtn.click();
                repliedCount++;
                updateStatusUI(`✅ پاسخ خودکار ارسال شد`);
            } else {
                // اگر دکمه یافت نشد، کلید Enter را شبیه‌سازی می‌کنیم
                inputEl.dispatchEvent(new KeyboardEvent('keydown', { keyCode: 13, bubbles: true }));
                repliedCount++;
                updateStatusUI(`✅ پاسخ خودکار ارسال شد`);
            }
        }, 500);
    }

    // -------------------------------------------------------------
    // پارسر صورتحساب
    // -------------------------------------------------------------
    function parseMessageContent(text) {
        const cleanText = text.trim();
        const parsed = {
            raw_text: cleanText,
            timestamp: new Date().toISOString(),
            bank_name: null,
            amount: null,
            tracking_number: null,
            sender: null,
            receiver: null,
            destination_iban: null,
            date: null,
            phone_numbers: []
        };

        const bankMatch = cleanText.match(/(بانک\s+[\u0600-\u06FF]+|بلوبانک|بانکت)/);
        if (bankMatch) parsed.bank_name = bankMatch[0];

        const amountMatch = cleanText.match(/مبلغ[:\s]*([\d,۰-۹]+)\s*(ریال|تومان)?/);
        if (amountMatch) parsed.amount = amountMatch[1].replace(/[,,/]/g, '');

        const trackMatch = cleanText.match(/(?:شماره|کد)\s*پیگیری[:\s]*([\d۰-۹]+)/);
        if (trackMatch) parsed.tracking_number = trackMatch[1];

        const phones = cleanText.match(/(?:09|۰۹)[\d۰-۹]{9}/g);
        if (phones) parsed.phone_numbers = Array.from(new Set(phones));

        return parsed;
    }

    // -------------------------------------------------------------
    // اسکن و پایش پیام‌های روبیکا
    // -------------------------------------------------------------
    function scanMessages() {
        const targetElements = document.querySelectorAll('div[rb-copyable], div[style*="unicode-bidi"]');

        targetElements.forEach(el => {
            const bubbleGroup = el.closest('[data-msg-id]') || el.closest('.bubbles-group');
            const msgId = bubbleGroup ? bubbleGroup.getAttribute('data-msg-id') : null;
            const textContent = (el.innerText || el.textContent || '').trim();
            const uniqueKey = msgId || textContent;

            if (textContent && !processedMsgKeys.has(uniqueKey)) {
                processedMsgKeys.add(uniqueKey);

                // ۱. بررسی صورتحساب بودن پیام و ارسال به ماژول تخفیف
                if (textContent.includes("رسید") || textContent.includes("مبلغ") || textContent.includes("پیگیری")) {
                    const parsedData = parseMessageContent(textContent);
                    parsedData.msg_id = msgId;

                    if (typeof GM_xmlhttpRequest !== "undefined") {
                        GM_xmlhttpRequest({
                            method: "POST",
                            url: API_RECEIPTS,
                            headers: { "Content-Type": "application/json" },
                            data: JSON.stringify(parsedData),
                            onload: function() {
                                extractedCount++;
                                updateStatusUI(`✅ صورتحساب ثبت شد`);
                            }
                        });
                    }
                }

                // ۲. بررسی پاسخگوی هوشمند بر اساس کلمات کلیدی
                for (let rule of autoRules) {
                    if (rule.keyword && textContent.includes(rule.keyword.trim())) {
                        console.log(`🎯 تطابق کلمه کلیدی "${rule.keyword}": ارسال پاسخ خودکار...`);
                        sendAutoReplyInRubika(rule.response_text);
                        break; // ارسال اولین پاسخ منطبق
                    }
                }
            }
        });
    }

    // دریافت اولیه قوانین و شرووع پایش
    fetchAutoRules();
    setInterval(fetchAutoRules, 30000); // بروزرسانی قوانین هر ۳۰ ثانیه

    const observer = new MutationObserver(() => scanMessages());
    observer.observe(document.body, { childList: true, subtree: true });

    setTimeout(scanMessages, 2000);
    setInterval(scanMessages, 3000);

})();
