import '../models/coupon.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 내 쿠폰 엔드포인트. 쿠폰 지급은 서버(완주 인증·운영자) 몫이다.
class CouponApi {
  CouponApi(this._client);

  final ApiClient _client;

  /// 내 쿠폰 목록(최신순).
  Future<List<Coupon>> fetchMyCoupons() async {
    final response = await _client.dio.get('/me/coupons');
    return parseList(response.data, Coupon.fromJson);
  }

  Future<Coupon> fetchCoupon(String couponId) async {
    final response = await _client.dio.get('/me/coupons/$couponId');
    return Coupon.fromJson(response.data as Map<String, dynamic>);
  }

  /// 고른 업체에서 사용(이용완료) 처리. 사용된 쿠폰을 돌려준다.
  Future<Coupon> useCoupon(String couponId, {required String partnerId}) async {
    final response = await _client.dio.post(
      '/me/coupons/$couponId/use',
      data: {'partner_id': partnerId},
    );
    return Coupon.fromJson(response.data as Map<String, dynamic>);
  }
}
