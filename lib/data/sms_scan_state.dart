/// Persisted SMS scan progress for resume and incremental sync.
class SmsScanState {
  const SmsScanState({
    this.fullScanComplete = false,
    this.resumeOffset = 0,
    this.lastScanAt,
    this.scanSinceMs,
  });

  final bool fullScanComplete;
  final int resumeOffset;
  final DateTime? lastScanAt;
  final int? scanSinceMs;

  SmsScanState copyWith({
    bool? fullScanComplete,
    int? resumeOffset,
    DateTime? lastScanAt,
    int? scanSinceMs,
  }) {
    return SmsScanState(
      fullScanComplete: fullScanComplete ?? this.fullScanComplete,
      resumeOffset: resumeOffset ?? this.resumeOffset,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      scanSinceMs: scanSinceMs ?? this.scanSinceMs,
    );
  }
}
