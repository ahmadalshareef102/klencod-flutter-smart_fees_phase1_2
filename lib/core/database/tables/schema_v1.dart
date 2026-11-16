/// مخطط قاعدة البيانات - الإصدار 1.
/// كل المبالغ INTEGER بوحدة الريال. التواريخ نصوص ISO (yyyy-MM-dd) والطوابع UTC.
const String _ts =
    "TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))";

const List<String> schemaV1 = [
  // ---------------------------------------------------------------- المعهد
  '''
CREATE TABLE institutes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  logo_path TEXT,
  manager_name TEXT,
  phone TEXT,
  address TEXT,
  email TEXT,
  currency TEXT NOT NULL DEFAULT 'YER',
  academic_year TEXT,
  created_at $_ts,
  updated_at $_ts
)''',
  '''
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at $_ts
)''',
  '''
CREATE TABLE admin_users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  institute_id INTEGER REFERENCES institutes(id),
  name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until TEXT,
  created_at $_ts,
  updated_at $_ts
)''',

  // --------------------------------------------------------------- الطلاب
  '''
CREATE TABLE students (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  institute_id INTEGER REFERENCES institutes(id),
  student_no TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL CHECK (length(trim(full_name)) > 0),
  gender TEXT CHECK (gender IN ('male','female') OR gender IS NULL),
  phone TEXT,
  guardian_phone TEXT,
  address TEXT,
  birth_date TEXT,
  registered_at TEXT NOT NULL DEFAULT (date('now')),
  photo_path TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','suspended','graduated','withdrawn')),
  created_at $_ts,
  updated_at $_ts,
  deleted_at TEXT
)''',
  'CREATE INDEX idx_students_name ON students(full_name)',
  'CREATE INDEX idx_students_phone ON students(phone)',
  'CREATE INDEX idx_students_status ON students(status)',

  // --------------------------------------------------- الدورات والدفعات
  '''
CREATE TABLE courses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  institute_id INTEGER REFERENCES institutes(id),
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  description TEXT,
  duration TEXT,
  default_fee INTEGER NOT NULL DEFAULT 0 CHECK (default_fee >= 0),
  hours INTEGER CHECK (hours IS NULL OR hours >= 0),
  level TEXT,
  start_date TEXT,
  end_date TEXT,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','suspended','archived')),
  created_at $_ts,
  updated_at $_ts,
  deleted_at TEXT
)''',
  'CREATE INDEX idx_courses_name ON courses(name)',
  '''
CREATE TABLE batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  course_id INTEGER NOT NULL REFERENCES courses(id),
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  level TEXT,
  trainer TEXT,
  start_date TEXT,
  end_date TEXT,
  study_days TEXT,
  start_time TEXT,
  end_time TEXT,
  capacity INTEGER CHECK (capacity IS NULL OR capacity > 0),
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','closed','archived')),
  created_at $_ts,
  updated_at $_ts,
  deleted_at TEXT
)''',
  'CREATE INDEX idx_batches_course ON batches(course_id)',

  // ------------------------------------------------------------ التسجيلات
  // الرسوم تُحفظ كما كانت لحظة التسجيل ولا ترتبط بسعر الدورة الحالي.
  '''
CREATE TABLE enrollments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id INTEGER NOT NULL REFERENCES students(id),
  course_id INTEGER NOT NULL REFERENCES courses(id),
  batch_id INTEGER REFERENCES batches(id),
  enrolled_at TEXT NOT NULL DEFAULT (date('now')),
  original_fee INTEGER NOT NULL CHECK (original_fee >= 0),
  discount INTEGER NOT NULL DEFAULT 0 CHECK (discount >= 0),
  extra_fee INTEGER NOT NULL DEFAULT 0 CHECK (extra_fee >= 0),
  final_fee INTEGER NOT NULL CHECK (final_fee >= 0),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','completed','withdrawn','cancelled')),
  notes TEXT,
  created_at $_ts,
  updated_at $_ts,
  CHECK (final_fee = original_fee - discount + extra_fee)
)''',
  'CREATE INDEX idx_enrollments_student ON enrollments(student_id)',
  'CREATE INDEX idx_enrollments_batch ON enrollments(batch_id)',
  // سجل تاريخي لتغيير الدفعة/الدورة حتى لا يضيع التاريخ السابق.
  '''
CREATE TABLE enrollment_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  enrollment_id INTEGER NOT NULL REFERENCES enrollments(id),
  old_course_id INTEGER,
  old_batch_id INTEGER,
  new_course_id INTEGER,
  new_batch_id INTEGER,
  reason TEXT,
  changed_at $_ts
)''',

  // ---------------------------------------------------- الرسوم والأقساط
  '''
CREATE TABLE fee_plans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  enrollment_id INTEGER NOT NULL UNIQUE REFERENCES enrollments(id),
  installments_count INTEGER NOT NULL CHECK (installments_count > 0),
  first_due_date TEXT NOT NULL,
  interval_days INTEGER NOT NULL CHECK (interval_days > 0),
  total_amount INTEGER NOT NULL CHECK (total_amount >= 0),
  created_at $_ts
)''',
  '''
CREATE TABLE installments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fee_plan_id INTEGER NOT NULL REFERENCES fee_plans(id),
  enrollment_id INTEGER NOT NULL REFERENCES enrollments(id),
  seq INTEGER NOT NULL CHECK (seq > 0),
  amount INTEGER NOT NULL CHECK (amount > 0),
  due_date TEXT NOT NULL,
  paid_amount INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'not_due'
    CHECK (status IN ('not_due','due','partial','paid','late')),
  created_at $_ts,
  updated_at $_ts,
  UNIQUE (fee_plan_id, seq),
  CHECK (paid_amount >= 0 AND paid_amount <= amount)
)''',
  'CREATE INDEX idx_installments_enrollment ON installments(enrollment_id)',
  'CREATE INDEX idx_installments_due ON installments(due_date)',

  // --------------------------------------------------------- المدفوعات
  '''
CREATE TABLE payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  enrollment_id INTEGER NOT NULL REFERENCES enrollments(id),
  amount INTEGER NOT NULL CHECK (amount > 0),
  paid_at TEXT NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('cash','transfer','other')),
  receipt_no TEXT NOT NULL UNIQUE,
  receiver_name TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','reversed')),
  reversal_reason TEXT,
  reversed_at TEXT,
  created_by INTEGER REFERENCES admin_users(id),
  created_at $_ts,
  updated_at $_ts,
  CHECK (status = 'active'
         OR (reversal_reason IS NOT NULL AND length(trim(reversal_reason)) > 0))
)''',
  'CREATE INDEX idx_payments_enrollment ON payments(enrollment_id)',
  'CREATE INDEX idx_payments_paid_at ON payments(paid_at)',
  // installment_id = NULL يعني دفعة على الحساب (بدون قسط محدد).
  '''
CREATE TABLE payment_allocations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_id INTEGER NOT NULL REFERENCES payments(id),
  installment_id INTEGER REFERENCES installments(id),
  amount INTEGER NOT NULL CHECK (amount > 0),
  reversed_at TEXT,
  created_at $_ts
)''',
  'CREATE INDEX idx_alloc_payment ON payment_allocations(payment_id)',
  'CREATE INDEX idx_alloc_installment ON payment_allocations(installment_id)',
  '''
CREATE TABLE receipts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_id INTEGER NOT NULL UNIQUE REFERENCES payments(id),
  receipt_no TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled')),
  issued_at $_ts,
  printed_count INTEGER NOT NULL DEFAULT 0 CHECK (printed_count >= 0)
)''',

  // ------------------------------------------------------------- الحضور
  '''
CREATE TABLE attendance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  enrollment_id INTEGER NOT NULL REFERENCES enrollments(id),
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  date TEXT NOT NULL,
  session INTEGER NOT NULL DEFAULT 1 CHECK (session > 0),
  status TEXT NOT NULL
    CHECK (status IN ('present','absent','late','excused','leave')),
  notes TEXT,
  created_at $_ts,
  updated_at $_ts,
  UNIQUE (enrollment_id, date, session)
)''',
  'CREATE INDEX idx_attendance_batch_date ON attendance(batch_id, date)',

  // ----------------------------------------------------------- المصروفات
  '''
CREATE TABLE expense_categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1)),
  created_at $_ts,
  deleted_at TEXT
)''',
  '''
CREATE TABLE expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category_id INTEGER NOT NULL REFERENCES expense_categories(id),
  amount INTEGER NOT NULL CHECK (amount > 0),
  spent_at TEXT NOT NULL,
  description TEXT,
  method TEXT NOT NULL DEFAULT 'cash' CHECK (method IN ('cash','transfer','other')),
  attachment_path TEXT,
  notes TEXT,
  created_at $_ts,
  updated_at $_ts,
  deleted_at TEXT
)''',
  'CREATE INDEX idx_expenses_spent_at ON expenses(spent_at)',

  // ------------------------------------------- الإشعارات والتدقيق والنسخ
  '''
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  installment_id INTEGER REFERENCES installments(id),
  kind TEXT NOT NULL,
  scheduled_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','delivered','cancelled')),
  created_at $_ts
)''',
  '''
CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id INTEGER,
  action TEXT NOT NULL,
  details TEXT,
  actor_id INTEGER,
  created_at $_ts
)''',
  'CREATE INDEX idx_audit_entity ON audit_logs(entity, entity_id)',
  '''
CREATE TABLE backup_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_name TEXT NOT NULL,
  size_bytes INTEGER NOT NULL CHECK (size_bytes >= 0),
  checksum TEXT,
  schema_version INTEGER NOT NULL,
  encrypted INTEGER NOT NULL DEFAULT 0 CHECK (encrypted IN (0,1)),
  kind TEXT NOT NULL DEFAULT 'backup' CHECK (kind IN ('backup','restore_safety')),
  created_at $_ts
)''',

  // ------------------- حماية السجلات المالية: لا حذف نهائي ولا تعديل للتدقيق
  '''
CREATE TRIGGER trg_payments_no_delete BEFORE DELETE ON payments
BEGIN SELECT RAISE(ABORT, 'لا يجوز حذف العمليات المالية؛ استخدم عكس العملية'); END''',
  '''
CREATE TRIGGER trg_allocations_no_delete BEFORE DELETE ON payment_allocations
BEGIN SELECT RAISE(ABORT, 'لا يجوز حذف تخصيصات الدفعات'); END''',
  '''
CREATE TRIGGER trg_receipts_no_delete BEFORE DELETE ON receipts
BEGIN SELECT RAISE(ABORT, 'لا يجوز حذف سندات القبض؛ يمكن إلغاؤها فقط'); END''',
  '''
CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON audit_logs
BEGIN SELECT RAISE(ABORT, 'سجل التدقيق غير قابل للحذف'); END''',
  '''
CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON audit_logs
BEGIN SELECT RAISE(ABORT, 'سجل التدقيق غير قابل للتعديل'); END''',

  // ------------------------------------------------ إعدادات وتصنيفات أولية
  // هذه إعدادات تشغيلية وليست بيانات وهمية.
  "INSERT INTO app_settings(key, value) VALUES ('receipt_seq', '0')",
  '''
INSERT INTO expense_categories(name, is_default) VALUES
  ('رواتب المدربين', 1), ('الإيجار', 1), ('الكهرباء', 1), ('الإنترنت', 1),
  ('المشتريات', 1), ('الصيانة', 1), ('مصروفات أخرى', 1)''',
];
