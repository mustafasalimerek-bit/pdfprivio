/// Cooperative cancellation flag for long-running operations.
///
/// Services check `isCancelled` at safe boundaries (file boundaries, page
/// boundaries) and abort early. The UI keeps a reference to the token so the
/// user's "Cancel" button can flip the flag.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}
