/// Outcome of an operation that can fail with a user-facing reason.
///
/// We prefer this over exceptions for service-layer APIs because:
/// 1. Forces callers to handle the failure case at compile time.
/// 2. Carries a category we can map to a recovery action ("retry",
///    "enter password", "free storage").
/// 3. Plays nicely with Riverpod state (success/failure are values, not
///    thrown control flow).
sealed class Result<T> {
  const Result();
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final FailureKind kind;
  final String message;
  final Object? cause;
  const Err(this.kind, this.message, {this.cause});
}

enum FailureKind {
  /// User cancelled (closed picker, hit cancel mid-operation).
  cancelled,

  /// PDF is password-protected and we don't have the password.
  needsPassword,

  /// File is corrupted; recovery may be possible — PdfRepairService can try.
  corrupted,

  /// Operation requires Pro entitlement.
  needsPro,

  /// Out of disk space.
  diskFull,

  /// Memory pressure; consider closing other apps or splitting the job.
  outOfMemory,

  /// Unknown error — capture in Crashlytics with cause attached.
  unknown,
}
