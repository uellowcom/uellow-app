# دليل جلب مفاتيح البحث عن صور المنتجات — Uellow Smart Connector

هذا المفتاح يجعل الاستيراد يجلب **عدة صور عالية الدقّة** لكل منتج تلقائياً (بدلاً من صورة واحدة).
اختر **مزوّداً واحداً** فقط. الأسهل = **SerpAPI**. الأرخص على المدى الطويل = **Google CSE**.

## أين تُلصق المفاتيح داخل Uellow
**Smart Connector ← Settings ← قسم Image Search:**
- `Image Search Provider` = اختر المزوّد
- `Image Search API Key` = الصِق المفتاح
- `Google CSE Engine ID (cx)` = (فقط مع Google CSE)
- `Images per Search` = 8 (افتراضي — كم صورة يبحث عنها)

---

## الخيار 1 — SerpAPI (الأسهل، يوصى به للبداية)
1. افتح https://serpapi.com وأنشئ حساباً (Sign Up).
2. فعّل بريدك، ثم ادخل لوحة التحكم.
3. من القائمة: **Api Key** → انسخ المفتاح (يبدأ بأحرف/أرقام طويلة).
4. في Uellow: Provider = **SerpAPI (Google Images)**، والصِق المفتاح في `Image Search API Key`.
- الباقة المجانية: ~100 بحث/شهر. للاستيراد الكثيف اختر باقة مدفوعة.
- مميزات: لا يحتاج إعداد إضافي، يرجّع صور Google عالية الجودة مباشرة.

---

## الخيار 2 — Google Programmable Search (CSE) — يحتاج شيئين: API Key + Engine ID (cx)
**أ) إنشاء محرّك البحث (cx):**
1. افتح https://programmablesearchengine.google.com/controlpanel/create
2. اسم المحرّك: Uellow Images. في "Search the entire web" فعّلها (Search the whole web).
3. فعّل **Image search = ON**.
4. أنشئه، ثم من **Edit ← Basics** انسخ **Search engine ID** (هذا هو الـ`cx`).

**ب) إنشاء API Key:**
1. افتح https://console.cloud.google.com → أنشئ مشروعاً (أو اختر موجوداً).
2. **APIs & Services ← Library** → ابحث **Custom Search API** → **Enable**.
3. **APIs & Services ← Credentials ← Create Credentials ← API key** → انسخ المفتاح.

**ج) في Uellow:**
- Provider = **Google Programmable Search (CSE)**
- `Image Search API Key` = مفتاح الـAPI
- `Google CSE Engine ID (cx)` = الـSearch engine ID
- الباقة المجانية: 100 بحث/يوم مجاناً، ثم رسوم بسيطة لكل 1000.

---

## الخيار 3 — Bing Image Search
1. افتح https://portal.azure.com → أنشئ مورد **Bing Search v7** (Microsoft/Azure Marketplace).
2. بعد الإنشاء: **Keys and Endpoint** → انسخ **Key 1**.
3. في Uellow: Provider = **Bing Image Search**، والصِق المفتاح في `Image Search API Key`.
- ملاحظة: مايكروسوفت تنقل خدمة Bing Search؛ قد يتطلّب إعداداً إضافياً.

---

## بعد إضافة المفتاح
- الاستيرادات الجديدة ستجلب 3–8 صور لكل منتج (1 رئيسية + معرض) عالية الدقّة.
- لإثراء **المنتجات المستوردة سابقاً** ذات الصورة الواحدة/الضعيفة: أرسِل لي رسالة «شغّل Backfill الصور» وأبني أداة تضيف صوراً للمنتجات الموجودة (إضافة فقط، لا تحذف الأصلية).

## توصية سريعة
ابدأ بـ **SerpAPI** (أسرع تجهيز). لو الحجم كبير وتريد تكلفة أقل لاحقاً، انتقل لـ **Google CSE**.
أرسِل لي المفتاح (أو فعّله بنفسك من الشاشة أعلاه) وأكمل التهيئة + الـBackfill فوراً.
