# Supermarket ERP

خادم Dart مركزي وعقود مشتركة لنظام سوبر ماركت، مع خطة Flutter Android / Windows / Web وPostgreSQL وFirebase.

**الحالة الحالية: الدفعة الخادمية من الدورة الأولى. واجهات Flutter والتخزين المحلي وPDF لم تُنفذ بعد في هذه الدفعة.**

- [حالة التنفيذ ونقطة الاستئناف](docs/IMPLEMENTATION_STATUS.md)
- [سجل التنفيذ التفصيلي](docs/EXECUTION_LOG.md)
- [نتائج الاختبارات وحدود التحقق](docs/VALIDATION_REPORT.md)
- [المعمارية وADR-001](docs/ITERATION_01_ARCHITECTURE_AND_DIAGRAMS.md)
- [عقد OpenAPI](docs/openapi_v1.yaml)
- [المهام المتسلسلة](https://github.com/abdallah1mohmmed2/Super-market/issues)

## تشغيل الخادم

المتطلبات: Dart 3.13.7 وPostgreSQL 16، ومشروع Firebase Auth مع مستخدم مسجل. لا يُنشأ مدير أو فرع تلقائياً من تسجيل الدخول.

1. من مجلد `server` نفذ `dart pub get --enforce-lockfile`.
2. عيّن `DATABASE_URL` لاتصال PostgreSQL الخاص بك. مثال التطوير المحلي فقط: `postgresql://erp_test:erp_test@127.0.0.1:5432/supermarket_test?sslmode=disable`. استخدم التحقق من TLS في الإنتاج.
3. نفذ `dart run bin/migrate.dart`. يتحقق من بصمة كل migration، ولا يطبق الملف نفسه مرتين. لا تعدل migration سبق تطبيقها؛ أضف ملفاً جديداً.
4. جهز المستخدم صراحة:

```sh
dart run bin/provision_user.dart FIREBASE_UID DISPLAY_NAME BRANCH_NAME ADMIN
```

استبدل الوسائط ببيانات المستخدم والفرع الفعلية. يتوقف الأمر عند UID موجود أو اسم فرع ملتبس بدلاً من تغيير صلاحيات حساب قائم.

5. عيّن `FIREBASE_PROJECT_ID` و`CORS_ORIGINS` كقائمة أصول مفصولة بفاصلة، ثم نفذ `dart run bin/server.dart`.
6. المسار العام `GET /health` يعيد صحة العملية. بقية عمليات الأصناف تحتاج Firebase ID token صالحاً وصلاحيات المستخدم المهيأ.

| متغير | الوظيفة |
|---|---|
| `DATABASE_URL` | اتصال PostgreSQL؛ مطلوب إلا في وضع الذاكرة الصريح |
| `FIREBASE_PROJECT_ID` | المشروع المقبول في aud وiss؛ مطلوب دائماً |
| `HOST` / `PORT` | الافتراضي 127.0.0.1:8080؛ الحاوية تستخدم 0.0.0.0 |
| `CORS_ORIGINS` | أصول المتصفح المسموحة؛ النجمة غير مقبولة |
| `APP_ENV` | استخدم production لمنع التخزين المؤقت في الإنتاج |
| `CATALOG_STORAGE` | memory للتطوير فقط؛ وإلا PostgreSQL |
| `DEV_FIREBASE_UID` | تهيئة حساب تطوير صريح في الذاكرة مع توكن Firebase حقيقي |
| `REPORT_COUNTRY` / `SUPERMARKET_NAME` | إعدادات ترويسة التقرير اللاحق |

وضع الذاكرة يفقد بياناته عند إيقاف العملية، ولا يحتوي أصنافاً أو عملاء تجريبيين. لا يوجد تجاوز للتحقق من توقيع Firebase في ملف تشغيل الخادم؛ المحقق الوهمي موجود في الاختبارات فقط.

## العقود

- `X-Request-Id` مطلوب للطلبات المؤمنة، و`Authorization: Bearer` يحمل Firebase ID token.
- كل POST يحتاج `Idempotency-Key` من UUID v4؛ يجب الاحتفاظ بالمفتاح نفسه عند retry.
- حفظ الأصناف يستخدم revision متوقعاً؛ تعارض الإصدار أو إعادة استعمال المفتاح بمحتوى مختلف يرجع409.
- الأسعار نص عشري ثابت مثل `150.00`، ومعامل الوحدة موجب حتى6 منازل عشرية. إنشاء تعريف الصنف لا يخلق مخزوناً.
- سقف الصفحة30، مع cursor وETag و304. البحث والباركود وPLU معزولة بحسب فرع الجلسة.
- `POST /v1/auth/session` لا يغير البيانات؛ يعيد الصلاحيات الحالية، ولا يخزن جواباً قديماً للجلسة.

## الفحص المحلي

من كل حزمة (`packages/core_contracts` و`packages/api_client` و`server`) نفذ `dart pub get --enforce-lockfile` ثم `dart analyze` ثم `dart test`.

لاختبارات PostgreSQL: استخدم قاعدة اختبار مخصصة، طبق migration، ثم عيّن `TEST_DATABASE_URL` وأعد `dart test` في `server`. إذا لم يُضبط المتغير، تظهر اختبارات PostgreSQL متخطاة صراحة؛ لا يُعد ذلك تحققاً من قاعدة فعلية.

من جذر المستودع:

```sh
dart format --output=none --set-exit-if-changed packages server
python -m pip install -r tools/requirements-checks.txt
python tools/validate_openapi.py
```

يتطلب فحص OpenAPI تشغيل اختبارات الخادم أولاً لتوليد الردود الحقيقية. ملف العقد مكتوب بصيغة JSON المتوافقة مع YAML1.2، ويعاد توليده بواسطة `python tools/write_openapi.py`.

بناء الخادم من `server`:

```sh
dart compile exe bin/server.dart -o build/supermarket-server
```

ملف GitHub Actions الحالي يفحص الخادم والعقود وينتج تنفيذي Linux فقط. الحزم الثلاث للتطبيق وخط الفحص الشامل ستضاف بعد تنفيذ Flutter والتحقق منه. Dockerfile جاهز للبناء بسياق جذر المستودع (`docker build -f server/Dockerfile .`)، لكن بناء الحاوية لم يُختبر محلياً بعد.
