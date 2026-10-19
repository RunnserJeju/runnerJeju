import 'package:dio/dio.dart';

import '../api/coupon_api.dart';
import '../exceptions/app_exception.dart';
import '../models/coupon.dart';

/// 유효기간이 지난 쿠폰을 쓰려 한 경우(서버 410). 서버가 만료로 기록했으니 화면은
/// 그 쿠폰을 목록에서 치운다.
class CouponExpiredException extends AppException {
  CouponExpiredException([Object? cause]) : super('유효기간이 지난 쿠폰이에요.', cause);
}

/// 비즈니스 로직 계층: 내 쿠폰 조회·사용.
class CouponService {
  CouponService(this._couponApi);

  final CouponApi _couponApi;

  Future<List<Coupon>> loadMyCoupons() async {
    try {
      return await _couponApi.fetchMyCoupons();
    } catch (e) {
      throw AppException('쿠폰을 불러오지 못했어요.', e);
    }
  }

  Future<Coupon> loadCoupon(String couponId) async {
    try {
      return await _couponApi.fetchCoupon(couponId);
    } catch (e) {
      throw AppException('쿠폰 정보를 불러오지 못했어요.', e);
    }
  }

  /// 업체 쿠폰 번호로 사용 처리. 서버가 거절 이유(번호 불일치·이미 사용·만료·업체
  /// 제한)를 문장으로 주면 그대로 보여준다.
  Future<Coupon> useCoupon(String couponId, {required String pin}) async {
    try {
      return await _couponApi.useCoupon(couponId, pin: pin);
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) throw CouponExpiredException(e);
      throw AppException(_serverMessage(e) ?? '쿠폰 사용에 실패했어요.', e);
    } catch (e) {
      throw AppException('쿠폰 사용에 실패했어요.', e);
    }
  }

  static String? _serverMessage(DioException e) {
    final detail = (e.response?.data as Map?)?['detail'];
    return detail is String ? detail : null;
  }
}
