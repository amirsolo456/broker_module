// ==UserScript==
// @name         Rubika Group Crawler & Smart Auto-Responder
// @namespace    http://tampermonkey.net/
// @version      4.0
// @description  خزنده زنده و فقط‌گروه‌هدف روبیکا + ارسال به Broker + پاسخ خودکار
// @match        https://web.rubika.ir/*
// @grant        GM_xmlhttpRequest
// @connect      *
// ==/UserScript==

(function () {
    'use strict';

    const SERVER_BASE = (typeof GM_getValue !== "undefined" && GM_getValue("SERVER_BASE")) || "http://10.0.2.2:5050";
    const API_RECEIPTS = SERVER_BASE + "/api/receipts";
    const API_RULES = SERVER_BASE + "/api/auto-responses";
    const API_CLAIM_REPLY = SERVER_BASE + "/api/auto-reply/claim";
    const TARGET_GROUP_ID = "g0HUhDZ03024bd85fad3e51ae86e52e8";

    const SCAN_INTERVAL_MS = 2500;
    const HISTORY_SCROLL_INTERVAL_MS = 20000;
    const HISTORY_SCROLL_WAIT_MS = 1200;

    const processedMsgKeys = new Set();
    const inFlightMsgKeys = new Set();
    let autoRules = [];
    let extractedCount = 0;
    let repliedCount = 0;

    const statusBox = document.createElement('div');
    statusBox.style.cssText =
        'position:fixed;bottom:20px;left:20px;z-index:99999;' +
        'background:#1e1e2e;color:#cdd6f4;padding:12px 16px;border-radius:10px;' +
        'box-shadow:0 4px 15px rgba(0,0,0,0.3);font-family:Tahoma,Vazir,sans-serif;' +
        'font-size:12px;direction:rtl;min-width:240px;';

    statusBox.innerHTML =
        '<div style="font-weight:bold;margin-bottom:5px;color:#89b4fa;">🤖 خزنده گروه روبیکا</div>' +
        '<div id="rb-bot-status">در حال بارگذاری...</div>' +
        '<div id="rb-bot-count" style="font-size:11px;color:#a6adc8;margin-top:4px;">پیام: 0 | پاسخ: 0</div>';

    document.body.appendChild(statusBox);

    function updateStatusUI(statusText) {
        const statusEl = document.getElementById('rb-bot-status');
        const countEl = document.getElementById('rb-bot-count');

        if (statusEl) statusEl.innerText = statusText;
        if (countEl) {
            countEl.innerText = 'پیام: ' + extractedCount + ' | پاسخ: ' + repliedCount;
        }
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
                        updateStatusUI(isTargetGroupOpen()
                            ? 'گروه هدف فعال است؛ خزنده روشن'
                            : 'گروه هدف باز نیست');
                    }
                } catch (e) {
                    updateStatusUI("خطا در خواندن قوانین");
                }
            },
            onerror: function () {
                updateStatusUI("سرور Broker در دسترس نیست");
            }
        });
    }

    function getTargetRoot() {
        return document.querySelector(
            '[data-chat-id="' + TARGET_GROUP_ID + '"]'
        );
    }

    function isTargetGroupOpen() {
        return !!getTargetRoot();
    }

    function crawlHistory() {
        const root = getTargetRoot();
        if (!root) {
            updateStatusUI("⏳ گروه هدف هنوز باز/لود نشده");
            return;
        }

        let candidates = [root].concat(Array.from(root.querySelectorAll('*')));

        candidates = candidates.filter(function (el) {
            const style = window.getComputedStyle(el);
            return el.scrollHeight > el.clientHeight + 80 &&
                (style.overflowY === 'auto' ||
                 style.overflowY === 'scroll' ||
                 el === root);
        });

        if (!candidates.length) return;

        candidates.sort(function (a, b) {
            return (b.scrollHeight - b.clientHeight) -
                   (a.scrollHeight - a.clientHeight);
        });

        const scroller = candidates[0];
        const before = scroller.scrollTop;

        scroller.scrollTop = 0;
        scroller.dispatchEvent(new Event('scroll', { bubbles: true }));

        if (Math.abs(before - scroller.scrollTop) > 1) {
            updateStatusUI("🔎 در حال خزیدن تاریخچه گروه...");
        }
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

                    if (json.success) {
                        processedMsgKeys.add(msgId);

                        if (json.id) {
                            extractedCount++;
                        }

                        updateStatusUI(json.message || "✅ پیام بررسی شد");
                    }
                } catch (e) {
                    updateStatusUI("⚠️ پاسخ Broker نامعتبر بود");
                }

                inFlightMsgKeys.delete(msgId);
            },
            onerror: function () {
                inFlightMsgKeys.delete(msgId);
                updateStatusUI("❌ خطا در ارسال پیام به Broker");
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
        const root = getTargetRoot();
        if (!root) {
            console.warn("⚠️ گروه هدف فعال نیست؛ پاسخ خودکار ارسال نشد.");
            return;
        }

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
        const root = getTargetRoot();

        if (!root) {
            updateStatusUI("⏳ گروه هدف هنوز باز/لود نشده");
            return;
        }

        const groups = root.querySelectorAll('[data-msg-id]');

        groups.forEach(function (group) {
            const msgId = group.getAttribute('data-msg-id');

            if (!msgId ||
                processedMsgKeys.has(msgId) ||
                inFlightMsgKeys.has(msgId)) {
                return;
            }

            const classes = (group.getAttribute('class') || '').toLowerCase();

            if (classes.includes('service')) {
                processedMsgKeys.add(msgId);
                return;
            }

            const textContent =
                (group.innerText || group.textContent || '').trim();

            if (!textContent) {
                processedMsgKeys.add(msgId);
                return;
            }

            inFlightMsgKeys.add(msgId);
            postMessage(msgId, textContent);

            if (classes.includes('is-sent')) {
                return;
            }

            for (const rule of autoRules) {
                const keyword = (rule.keyword || '').trim();
                const ruleId = Number(rule.id || 0);

                if (!keyword || !ruleId ||
                    !textContent.includes(keyword)) {
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
    setInterval(scanMessages, SCAN_INTERVAL_MS);

    setInterval(function () {
        crawlHistory();
        setTimeout(scanMessages, HISTORY_SCROLL_WAIT_MS);
    }, HISTORY_SCROLL_INTERVAL_MS);

    const observer = new MutationObserver(function () {
        scanMessages();
    });

    observer.observe(document.body, {
        childList: true,
        subtree: true
    });
})();
