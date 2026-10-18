import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/transient_messenger.dart';
import 'running_week.dart';

/// 러닝위크 참가 신청 폼. 저장되면 빙고판이 담긴 회차를 들고 돌아간다.
///
/// 이름·연락처는 개인정보라 동의를 받는다. 보관 기간(1년)은 서버
/// routers/running_weeks.PARTICIPATION_RETENTION과 같아야 한다.
class ParticipationFormScreen extends StatefulWidget {
  const ParticipationFormScreen({super.key, required this.week});

  final RunningWeek week;

  @override
  State<ParticipationFormScreen> createState() =>
      _ParticipationFormScreenState();
}

class _ParticipationFormScreenState extends State<ParticipationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _age = TextEditingController();
  final _messenger = TransientMessenger();

  Gender? _gender;
  Residence? _residence;
  bool _agreed = false;
  bool _submitting = false;

  static const _consentText =
      '러닝위크 운영(참가 확인, 경품 안내)을 위해 이름, 연락처, 성별, 나이, 거주지를 '
      '수집·이용합니다. 수집한 정보는 참가 신청일로부터 최대 1년 보관 후 폐기합니다. '
      '동의하지 않을 수 있으며, 동의하지 않으면 러닝위크에 참가할 수 없습니다.';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _age.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _agreed && _gender != null && _residence != null && !_submitting;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || !_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final joined = await Services.instance.runningWeek.participate(
        widget.week.id,
        ParticipationForm(
          name: _name.text.trim(),
          phone: _phone.text,
          gender: _gender!,
          age: int.parse(_age.text),
          residence: _residence!,
        ),
      );
      if (mounted) Navigator.of(context).pop(joined);
    } catch (e) {
      if (mounted) _messenger.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('러닝위크 참가 신청')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _label('이름'),
            TextFormField(
              controller: _name,
              maxLength: 50,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(counterText: ''),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? '이름을 입력해 주세요.' : null,
            ),
            _label('연락처'),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '010-0000-0000'),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 9 || digits.length > 11
                    ? '연락처를 확인해 주세요.'
                    : null;
              },
            ),
            _label('성별'),
            SegmentedButton<Gender>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Gender.male, label: Text('남')),
                ButtonSegment(value: Gender.female, label: Text('여')),
              ],
              selected: {?_gender},
              onSelectionChanged: (v) =>
                  setState(() => _gender = v.isEmpty ? null : v.first),
            ),
            _label('나이'),
            TextFormField(
              controller: _age,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(suffixText: '세'),
              validator: (v) {
                final age = int.tryParse(v ?? '');
                return age == null || age < 1 || age > 120
                    ? '나이를 확인해 주세요.'
                    : null;
              },
            ),
            _label('거주지'),
            SegmentedButton<Residence>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Residence.jeju, label: Text('도민')),
                ButtonSegment(value: Residence.nonJeju, label: Text('도외')),
              ],
              selected: {?_residence},
              onSelectionChanged: (v) =>
                  setState(() => _residence = v.isEmpty ? null : v.first),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                _consentText,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textBody,
                ),
              ),
            ),
            CheckboxListTile(
              value: _agreed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                '개인정보 수집·이용에 동의합니다 (필수)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onChanged: (v) => setState(() => _agreed = v ?? false),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('신청하기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),
  );
}
