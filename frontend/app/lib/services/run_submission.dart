import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/coupon.dart';
import '../models/run_record.dart';
import '../models/run_stamp.dart';
import '../models/run_verification.dart';
import '../models/user_log.dart';
import 'coupon_service.dart';
import 'run_journal.dart';
import 'run_service.dart';
import 'stamp_service.dart';
import 'user_log_service.dart';
import 'verification_service.dart';

/// 결과 화면이 띄워야 할 연출 하나. 화면이 꺼내 보여주고 비운다.
sealed class Celebration {
  const Celebration();
}

class StampCelebration extends Celebration {
  const StampCelebration(this.stamp);
  final RunStamp stamp;
}

class CouponCelebration extends Celebration {
  const CouponCelebration(this.coupon);
  final Coupon coupon;
}

class CouponMissCelebration extends Celebration {
  const CouponMissCelebration({required this.name, required this.benefit});
  final String name;
  final String benefit;
}

/// 완료된 러닝을 서버에 올리고 검증·보상 조회까지 끝내는 전역 작업.
///
/// 화면(RunResultScreen)은 이걸 구독해 그리기만 한다. 화면이 닫혀도 여기서 도는
/// 업로드·검증은 멈추지 않는다 — 결과 화면이 저장 중에 닫히면 검증이 생략되던
/// 문제(#104)를 막는다. 러닝 한 번에 하나만 돌고, 다음 submit이 상태를 덮어쓴다.
class RunSubmission extends ChangeNotifier {
  RunSubmission(
    this._run,
    this._verification,
    this._stamp,
    this._coupon,
    this._journal,
  );

  final RunService _run;
  final RunJournal _journal;
  final VerificationService _verification;
  final StampService _stamp;
  final CouponService _coupon;

  RunRecord? record;

  RunUploadResult? uploadResult;
  String? uploadError;
  bool uploading = false;

  /// 코스 러닝일 때만. 검증 실패는 저장을 되돌리지 않는다.
  RunVerification? verification;
  String? verificationError;
  bool verifying = false;

  RunStamp? earnedStamp;
  Coupon? earnedCoupon;
  final List<Coupon> runningWeekCoupons = [];

  /// 아직 화면에서 띄우지 않은 연출. 순서대로 띄운다.
  final List<Celebration> pendingCelebrations = [];

  // 재시도로 같은 검증을 다시 받아도 연출은 한 번만.
  bool _courseDrawCelebrated = false;
  bool _runningWeekCelebrated = false;

  bool get earnedStampAny =>
      uploadResult?.earnedStamp == true || verification?.earnedStampId != null;

  /// 새 러닝 기록 제출. 이전 러닝 상태는 전부 버린다.
  Future<void> submit(RunRecord newRecord) {
    record = newRecord;
    uploadResult = null;
    verification = null;
    verificationError = null;
    verifying = false;
    earnedStamp = null;
    earnedCoupon = null;
    runningWeekCoupons.clear();
    pendingCelebrations.clear();
    _courseDrawCelebrated = false;
    _runningWeekCelebrated = false;
    return _upload();
  }

  /// 업로드 실패 후 재시도. 같은 기록을 다시 올린다.
  Future<void> retryUpload() => _upload();

  Future<void> retryVerify() async {
    final runId = uploadResult?.record.id;
    final courseId = record?.courseId;
    if (runId == null || courseId == null) return;
    await _verify(runId: runId, courseId: courseId);
  }

  Future<void> _upload() async {
    final current = record;
    if (current == null) return;
    uploading = true;
    uploadError = null;
    notifyListeners();

    final RunUploadResult result;
    try {
      result = await _run.saveRecord(current);
    } catch (e) {
      writeLog(
        LogName.runUploadFailed,
        detail: {LogKeys.courseId: ?current.courseId, LogKeys.error: '$e'},
      );
      if (record != current) return; // 그새 다른 러닝이 제출됨
      uploadError = '$e';
      uploading = false;
      notifyListeners();
      return;
    }
    if (record != current) return;

    uploadResult = result;
    uploading = false;
    notifyListeners();
    // 서버가 받았으니 기기의 일지는 더 필요 없다.
    unawaited(_journal.discardIfIdle());

    // 서버가 업로드 시점에 검증까지 끝내면 스탬프가 여기서 온다. 코스 스탬프 연출을
    // 쿠폰보다 먼저 띄우려고 검증 응답을 기다리지 않고 바로 받는다.
    final stampId = result.earnedStampId;
    if (stampId != null) await _loadStamp(stampId);

    final runId = result.record.id;
    final courseId = current.courseId;
    if (runId != null && courseId != null) {
      await _verify(runId: runId, courseId: courseId);
    }
  }

  Future<void> _verify({required String runId, required String courseId}) async {
    verifying = true;
    verificationError = null;
    notifyListeners();

    final RunVerification result;
    try {
      result = await _verification.verify(runId: runId, courseId: courseId);
    } catch (e) {
      writeLog(
        LogName.runVerifyFailed,
        detail: {
          LogKeys.runId: runId,
          LogKeys.courseId: courseId,
          LogKeys.error: '$e',
        },
      );
      if (uploadResult?.record.id != runId) return;
      verificationError = '$e';
      verifying = false;
      notifyListeners();
      return;
    }
    if (uploadResult?.record.id != runId) return;

    verification = result;
    verifying = false;
    notifyListeners();

    // 스탬프는 업로드·검증 양쪽에서 올 수 있다. 이미 받아 둔 것이면 다시 부르지 않는다.
    final stampId = result.earnedStampId;
    if (stampId != null && earnedStamp == null) await _loadStamp(stampId);
    await _celebrateCourseDraw(result);
    await _celebrateRunningWeek(result);
  }

  /// 조회 실패는 무시한다. 획득 사실은 이미 알고 있고 스탬프 탭에서 볼 수 있다.
  Future<void> _loadStamp(String stampId) async {
    try {
      final stamp = await _stamp.loadStamp(stampId);
      if (earnedStamp != null) return;
      earnedStamp = stamp;
      pendingCelebrations.add(StampCelebration(stamp));
      notifyListeners();
    } catch (_) {}
  }

  /// 조회 실패는 무시한다. 마이페이지에서 다시 볼 수 있다.
  Future<void> _loadCoupon(String couponId, {bool runningWeek = false}) async {
    try {
      final coupon = await _coupon.loadCoupon(couponId);
      if (runningWeek) {
        runningWeekCoupons.add(coupon);
      } else {
        earnedCoupon = coupon;
      }
      pendingCelebrations.add(CouponCelebration(coupon));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _celebrateDraw(CouponDraw draw, {bool runningWeek = false}) async {
    if (draw.won) {
      await _loadCoupon(draw.userCouponId!, runningWeek: runningWeek);
    } else {
      pendingCelebrations.add(
        CouponMissCelebration(name: draw.name, benefit: draw.benefit),
      );
      notifyListeners();
    }
  }

  /// 코스완료 쿠폰 추첨. 구 서버는 추첨 목록이 없어 당첨 id로만 띄운다.
  Future<void> _celebrateCourseDraw(RunVerification v) async {
    if (_courseDrawCelebrated) return;
    final draws = v.courseDraws;
    if (draws.isEmpty) {
      final couponId = v.earnedCouponId;
      if (couponId != null && earnedCoupon == null) {
        _courseDrawCelebrated = true;
        await _loadCoupon(couponId);
      }
      return;
    }
    _courseDrawCelebrated = true;
    for (final draw in draws) {
      await _celebrateDraw(draw);
    }
  }

  /// 러닝위크 스탬프(코스 전용 → 빙고 줄 수 순) 다음 러닝위크 쿠폰(줄 리워드 → 스페셜).
  Future<void> _celebrateRunningWeek(RunVerification v) async {
    if (_runningWeekCelebrated) return;
    _runningWeekCelebrated = true;
    for (final stampId in v.earnedRunningWeekStampIds) {
      try {
        final stamp = await _stamp.loadStamp(stampId);
        pendingCelebrations.add(StampCelebration(stamp));
        notifyListeners();
      } catch (_) {}
    }
    final draws = v.runningWeekDraws;
    if (draws.isEmpty) {
      for (final couponId in v.runningWeekCouponIds) {
        await _loadCoupon(couponId, runningWeek: true);
      }
      return;
    }
    for (final draw in draws) {
      await _celebrateDraw(draw, runningWeek: true);
    }
  }
}
