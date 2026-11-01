# -*- coding: utf-8 -*-
"""Create the GitHub release v2.2.126 with the APK + AAB attached.
Reads the token from /root/secrets/ghtok, creates the release, uploads both
assets, prints the URL, then removes the token file. Safe to re-run: if the
release already exists it reuses it."""
import json
import os
import sys
import urllib.request

REPO = 'uellowcom/uellow-app'
TAG = 'v2.2.126'
TOKEN_FILE = '/root/secrets/ghtok'
ASSETS = [
    ('/tmp/uellow-v2.2.126-326.apk', 'application/vnd.android.package-archive'),
    ('/tmp/uellow-v2.2.126-326.aab', 'application/octet-stream'),
]
NOTES = """## Uellow v2.2.126 (build 326)

### 🎧 خدمة العملاء المباشرة (بينا ↔ وكيل بشري)
- تبديل بينا بين **مساعد ذكاء اصطناعي** و**وكيل بشري مباشر** داخل نفس الإطار (أيقونة/اسم/حالة/ألوان تتبدّل).
- الرد على العميل من **الأدمن كونسل** بنص/صورة/ملف/منتج + إشعارات فورية للطرفين.
- تبادل الصور والملفات من الجهتين + ترشيح منتجات تفاعلي داخل الشات.

### ⚙️ إدارة كاملة (من أودو: Sales → Customer Service)
- إعدادات، إحصائيات (graph/pivot)، أرشيف.
- حالات المحادثة: مفتوحة / معلّقة / تم حلها / منتهية.
- رسائل ترحيب وختام تلقائية + ردود سريعة جاهزة.

### ⭐ إضافات
- تقييم الخدمة (CSAT) بعد الحل.
- ساعات العمل + رد تلقائي خارج الدوام.
- اقتراح رد بالذكاء الاصطناعي للوكيل.

---
**المرفقات:** APK (تحميل مباشر) + AAB (Google Play).
"""


def api(method, url, token, data=None, ctype='application/json', binary=False):
    headers = {'Authorization': 'token ' + token,
               'Accept': 'application/vnd.github+json',
               'User-Agent': 'uellow-release'}
    if data is not None and not binary:
        data = json.dumps(data).encode('utf-8')
        headers['Content-Type'] = 'application/json'
    elif binary:
        headers['Content-Type'] = ctype
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read().decode('utf-8'))


def main():
    if not os.path.exists(TOKEN_FILE) or os.path.getsize(TOKEN_FILE) == 0:
        print('ERROR: token file missing/empty:', TOKEN_FILE)
        sys.exit(2)
    token = open(TOKEN_FILE).read().strip()
    base = 'https://api.github.com/repos/%s' % REPO
    # find or create the release
    rel = None
    try:
        rel = api('GET', base + '/releases/tags/' + TAG, token)
    except Exception:
        rel = None
    if not rel or not rel.get('id'):
        rel = api('POST', base + '/releases', token, data={
            'tag_name': TAG, 'target_commitish': 'main',
            'name': 'Uellow %s' % TAG, 'body': NOTES, 'draft': False, 'prerelease': False})
    rid = rel['id']
    print('release id:', rid)
    existing = {a['name'] for a in rel.get('assets', [])}
    for path, ctype in ASSETS:
        name = os.path.basename(path)
        if name in existing:
            print('skip (exists):', name)
            continue
        up = 'https://uploads.github.com/repos/%s/releases/%d/assets?name=%s' % (REPO, rid, name)
        with open(path, 'rb') as f:
            blob = f.read()
        res = api('POST', up, token, data=blob, ctype=ctype, binary=True)
        print('uploaded:', res.get('name'), res.get('size'))
    print('RELEASE_URL: https://github.com/%s/releases/tag/%s' % (REPO, TAG))


if __name__ == '__main__':
    main()
