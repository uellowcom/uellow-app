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

> 💡 إن وجدت هذا الخيار معقّداً، استخدم **SerpAPI** (الخيار 1) — لا يحتاج هذه الخطوات إطلاقاً.

**أ) إنشاء محرّك البحث (cx):**
1. افتح https://programmablesearchengine.google.com/controlpanel/create
2. في خانة **"Name your search engine"** اكتب: `Uellow Images`.
3. **مهم — خانة "What to search?":**
   - افتراضياً جوجل يجعل المحرّك يبحث في **مواقع محدّدة تكتبها أنت فقط** (وهذا غير مناسب لنا).
   - نحن نريده أن يبحث في **كل الإنترنت** ليجد صور أي منتج.
   - لذلك اختر الخيار **"Search the entire web"** (ابحث في الويب كله). إن لم يظهر لك وقت الإنشاء، لا تكتب أي موقع وأكمل الإنشاء — ثم فعّله من الخطوة (ج) بالأسفل.
4. أكمل التحقق (لست روبوت) واضغط **Create**.

**ب) نسخ الـEngine ID (هو الـ`cx`):**
1. بعد الإنشاء تظهر صفحة المحرّك. اضغط **Customize** أو **Edit**.
2. في تبويب **Overview / Basics** ستجد **"Search engine ID"** — انسخه. هذا هو الـ`cx`.

**ج) تأكيد إعدادين مهمّين (في نفس صفحة Overview/Basics):**
1. **Search the entire web** → اجعله **ON** (مفتاح أخضر). إن كان OFF فالمحرّك لن يجد صوراً.
2. **Image search** → اجعله **ON** (هذا يفعّل إرجاع الصور).
3. احفظ (Save) إن طُلب.

**د) إنشاء API Key:**
1. افتح https://console.cloud.google.com → أنشئ مشروعاً (أو اختر موجوداً).
2. **APIs & Services ← Library** → ابحث **Custom Search API** → **Enable**.
3. **APIs & Services ← Credentials ← Create Credentials ← API key** → انسخ المفتاح.

**هـ) في Uellow:**
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
