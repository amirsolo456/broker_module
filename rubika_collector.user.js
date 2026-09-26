// ==UserScript==
// @name         Rubika Receipt Extractor & Smart Auto-Responder
// @namespace    http://tampermonkey.net/
// @version      3.0
// @description  استخراج سفارش/رسید فقط از گروه هدف روبیکا + پاسخ خودکار
// @match        https://web.rubika.ir/*
// @grant        GM_xmlhttpRequest
// @connect      localhost
// ==/UserScript==

(function () {
    'use strict';

    const SERVER_BASE = "http://localhost:5050";
    const API_RECEIPTS = SERVER_BASE + "/api/receipts";
    const API_RULES = SERVER_BASE + "/api/auto-responses";
    const API_CLAIM_REPLY = SERVER_BASE + "/api/auto-reply/claim";
    const TARGET_GROUP_ID = "g0HUhDZ03024bd85fad3e51ae86e52e8";

    const processedMsgKeys = new Set();
    let autoRules = [];
    let extractedCount = 0;
    let repliedCount = 0;

    const statusBox = document.createElement('div');
    statusBox.style.cssText =
        'position:fixed;bottom:20px;left:20px;z-index:99999;' +
        'background:#1e1e2e;color:#cdd6f4;padding:12px 16px;border-radius:10px;' +
        'box-shadow:0 4px 15px rgba(0,0,0,0.3);font-family:Tahoma,Vazir,sans-serif;' +
        'font-size:12px;direction:rtl;min-width:220px;';

    statusBox.innerHTML =
        '<div style="font-weight:bold;margin-bottom:5px;color:#89b4fa;">🤖 ربات روبیکا</div>' +
        '<div id="rb-bot-status">در حال بارگذاری...</div>' +
        '<div id="rb-bot-count" style="font-size:11px;color:#a6adc8;margin-top:4px;">پیام: 0 | پاسخ: 0</div>';

    document.body.appendChild(statusBox);

    function updateStatusUI(statusText) {
        const statusEl = document.getElementById('rb-bot-status');
        const countEl = document.getElementById('rb-bot-count');

        if (statusEl) statusEl.innerText = statusText;
        if (countEl) countEl.innerText = 'پیام: ' + extractedCount + ' | پاسخ: ' + repliedCount;
    }

    function fetchAutoRules() {
        GM_xmlhttpRequest({
            method: "GET",
            url: API_RULES,
            onload: function (res) {
                try {
                    const json = JSON.parse(res.responseText);
                    if (json.success) {
                        autoRules = json.data || [];
                        if (isTargetGroupOpen()) {
                            updateStatusUI('گروه هدف فعال است؛ ' + autoRules.length + ' قانون');
                        } else {
                            updateStatusUI('گروه هدف باز نیست');
                        }
                    }
                } catch (e) {
                    updateStatusUI("خطا در خواندن قوانین");
                }
            },
            onerror: function () {
                updateStatusUI("سرور محلی در دسترس نیست");
            }
        });
    }

    function isTargetGroupOpen() {
        return !!document.querySelector('[data-chat-id="' + TARGET_GROUP_ID + '"]');
    }

    function postMessage(msgId, textContent) {
        GM_xmlhttpRequest({
            method: "POST",
            url: API_RECEIPTS,
            headers: { "Content-Type": "application/json; charset=utf-8" },
            data: JSON.stringify({
                msg_id: msgId,
                chat_id: TARGET_GROUP_ID,
                raw_text: textContent
            }),
            onload: function (res) {
                try {
                    const json = JSON.parse(res.responseText);
                    if (json.success && json.id) {
                        extractedCount++;
                        updateStatusUI(json.message || "✅ پیام ثبت شد");
                    }
                } catch (e) {}
            },
            onerror: function () {
                updateStatusUI("❌ خطا در ارسال پیام");
            }
        });
    }

    function claimAutoReply(msgId, ruleId, callback) {
        GM_xmlhttpRequest({
            method: "POST",
            url: API_CLAIM_REPLY,
            headers: { "Content-Type": "application/json; charset=utf-8" },
            data: JSON.stringify({
                msg_id: msgId,
                rule_id: ruleId
            }),
            onload: function (res) {
                try {
                    const json = JSON.parse(res.responseText);
                    callback(!!json.success && !!json.claimed);
                } catch (e) {
                    callback(false);
                }
            },
            onerror: function () {
                callback(false);
            }
        });
    }

    function sendAutoReplyInRubika(replyText) {
        const inputEl =
            document.querySelector('div[contenteditable="true"]') ||
            document.querySelector('.input-message-input') ||
            document.querySelector('.textbox-field-input');

        if (!inputEl) {
            console.warn("⚠️ کادر ارسال پیام پیدا نشد.");
            return;
        }

        inputEl.focus();
        inputEl.innerText = replyText;
        inputEl.dispatchEvent(new InputEvent('input', {
            bubbles: true,
            inputType: 'insertText',
            data: replyText
        }));

        setTimeout(function () {
            const sendBtn =
                document.querySelector('.btn-send') ||
                document.querySelector('.send-button') ||
                document.querySelector('i.icon-send') ||
                document.querySelector('[rb-send-button]');

            if (sendBtn) {
                sendBtn.click();
            } else {
                inputEl.dispatchEvent(new KeyboardEvent('keydown', {
                    key: 'Enter',
                    code: 'Enter',
                    keyCode: 13,
                    which: 13,
                    bubbles: true
                }));
            }

            repliedCount++;
            updateStatusUI("✅ پاسخ خودکار ارسال شد");
        }, 500);
    }

    function scanMessages() {
        const chatRoot = document.querySelector('[data-chat-id="' + TARGET_GROUP_ID + '"]');

        if (!chatRoot) {
            updateStatusUI("⏳ گروه هدف هنوز باز/لود نشده");
            return;
        }

        const groups = chatRoot.querySelectorAll('[data-msg-id]');

        groups.forEach(function (group) {
            const msgId = group.getAttribute('data-msg-id');

            if (!msgId || processedMsgKeys.has(msgId)) {
                return;
            }

            const classes = (group.getAttribute('class') || '').toLowerCase();
            processedMsgKeys.add(msgId);

            if (classes.includes('service')) {
                return;
            }

            const textContent = (group.innerText || group.textContent || '').trim();
            if (!textContent) {
                return;
            }

            postMessage(msgId, textContent);

            if (classes.includes('is-sent')) {
                return;
            }

            for (const rule of autoRules) {
                const keyword = (rule.keyword || '').trim();
                const ruleId = Number(rule.id || 0);

                if (!keyword || !ruleId || !textContent.includes(keyword)) {
                    continue;
                }

                claimAutoReply(msgId, ruleId, function (claimed) {
                    if (claimed) {
                        sendAutoReplyInRubika(rule.response_text || '');
                    }
                });

                break;
            }
        });
    }

    fetchAutoRules();
    setInterval(fetchAutoRules, 30000);
    setTimeout(scanMessages, 2000);
    setInterval(scanMessages, 3000);

    const observer = new MutationObserver(function () {
        scanMessages();
    });

    observer.observe(document.body, { childList: true, subtree: true });
})();
