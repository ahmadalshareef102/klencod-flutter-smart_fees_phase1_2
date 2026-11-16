# Smart Fees – إدارة الرسوم

الحالة: المرحلتان 1 و2 مكتوبتان. **لم يُشغَّل `flutter analyze` ولا الاختبارات ولا البناء** (Flutter غير متاح في بيئة الكتابة).

## التشغيل في Klencod (مرة واحدة)

1. أنشئ مشروعًا جديدًا فارغًا ليولّد مجلد android:
   `flutter create --project-name smart_fees --org com.smartfees --platforms android smart_fees_new`
2. انسخ فوقه من هذا المجلد: `lib/` و`test/` و`assets/` و`pubspec.yaml` و`analysis_options.yaml`، واحذف `test/widget_test.dart` المولَّد.
3. اضبط اسم الحزمة إلى `com.smartfees.management` في `android/app/build.gradle(.kts)` (`namespace` و`applicationId`) ومجلد/ملف `MainActivity` إن لزم، واضبط `android:label` إلى `Smart Fees` في `AndroidManifest.xml`.
4. ضع `Cairo-Regular.ttf` و`Cairo-Bold.ttf` في `assets/fonts/` وفعّل كتلة `fonts` في pubspec.
5. نفّذ بالترتيب:
   ```
   flutter pub get
   flutter analyze
   flutter test
   flutter run
   ```
6. أرسل لي أي خطأ بنصّه الأصلي لأصلحه.

## ما تم
- المرحلة 1: الثيم الفاتح/الداكن/التلقائي (محفوظ في SQLite)، RTL، شريط تنقل بخمسة عناصر، شاشة المزيد.
- المرحلة 2: 18 جدولًا (+ جدول `enrollment_history`)، Migrations، قيود CHECK/FK/UNIQUE، مفاتيح أجنبية مفعّلة، تريغرات تمنع حذف المدفوعات والسندات والتدقيق، `PaymentRepository` (تسجيل وعكس في معاملة واحدة)، `FeePlanRepository`، حسابات الأقساط.

## ملاحظات تصميم
- كل المبالغ أعداد صحيحة بالريال. الرصيد محسوب من الدفعات الفعّالة وليس مخزنًا.
- حالة القسط تُخزَّن عند آخر عملية؛ التقارير (مرحلة 6) ستعيد حسابها بتاريخ اليوم عبر `InstallmentCalculator.statusFor`.
- إنشاء خطة تقسيط بعد وجود دفعات على الحساب لا يربطها بالأقساط تلقائيًا (يُعالج في مرحلة 4).
- ملفات `light_theme/dark_theme` مدمجة في `app_theme.dart`، وبقية مجلدات المزايا تُنشأ عند الحاجة.
