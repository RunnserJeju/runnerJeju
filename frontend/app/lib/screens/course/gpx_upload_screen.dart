import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/course_facility.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import 'course_detail_screen.dart';

/// GPX 파일을 골라 코스로 등록한다 (관리자용 수동 업로드).
///
/// GPX는 경로 좌표와 이름만 갖고 있다. 거리·난이도·주소는 코스 명단
/// (server/courses/courses.yaml)에 적는 값과 같은 것이라 여기서 직접 입력받는다.
///
/// 주차장/화장실은 코스당 여러 개일 수 있어 동적 목록으로 입력받는다. 각 주소는
/// "확인"(GET /admin/geo/geocode)으로 좌표를 확보해야 등록된다 — 좌표 없는 시설은
/// 지도에 마커로 찍을 수 없기 때문이다.
///
/// [existing]을 주면 **수정 모드**가 된다 — 필드를 그 코스 값으로 채우고, 경로는
/// 바꿀 수 없으므로(이미 달린 사람의 검증 기준) GPX 파일 칸을 숨긴다. 제출하면
/// 업로드 대신 PATCH로 메타데이터만 수정하고, 수정된 코스를 pop으로 돌려준다.
class GpxUploadScreen extends StatefulWidget {
  const GpxUploadScreen({super.key, this.existing});

  /// 수정할 코스. null이면 신규 등록.
  final RunningCourse? existing;

  @override
  State<GpxUploadScreen> createState() => _GpxUploadScreenState();
}

class _GpxUploadScreenState extends State<GpxUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _distanceController = TextEditingController();
  final _addressController = TextEditingController();
  final _tagsController = TextEditingController();
  final _descriptionController = TextEditingController();

  final List<_FacilityRow> _parkingRows = [];
  final List<_FacilityRow> _restroomRows = [];

  CourseDifficulty _difficulty = CourseDifficulty.normal;
  PlatformFile? _pickedFile;
  bool _submitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _distanceController.text = existing.distanceKm.toString();
      _addressController.text = existing.address;
      _tagsController.text = existing.tags ?? '';
      _descriptionController.text = existing.description ?? '';
      _difficulty = existing.difficulty;
      _parkingRows.addAll(_rowsFrom(existing.parkings));
      _restroomRows.addAll(_rowsFrom(existing.restrooms));
    } else {
      // 빈 줄 하나씩 미리 둔다 — 대부분 코스가 주차장/화장실을 하나는 갖는다.
      _parkingRows.add(_FacilityRow());
      _restroomRows.add(_FacilityRow());
    }
  }

  /// 기존 시설 목록을 입력 행으로 바꾼다. 좌표가 이미 있으니 "확인됨" 상태로 시작해
  /// 다시 확인하지 않아도 저장된다. 비어 있으면 빈 줄 하나를 둔다.
  List<_FacilityRow> _rowsFrom(List<CourseFacility> facilities) {
    if (facilities.isEmpty) return [_FacilityRow()];
    return [
      for (final facility in facilities)
        (_FacilityRow()
          ..nameController.text = facility.name ?? ''
          ..addressController.text = facility.address
          ..confirmed = facility
          ..status = _CheckStatus.confirmed),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _distanceController.dispose();
    _addressController.dispose();
    _tagsController.dispose();
    _descriptionController.dispose();
    for (final row in [..._parkingRows, ..._restroomRows]) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );
    if (result == null) return;

    setState(() => _pickedFile = result.files.single);
  }

  /// 비어 있으면 null. 선택 입력 필드를 서버에 보낼 값으로 바꾼다.
  String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  List<FacilityFormEntry> _entries(List<_FacilityRow> rows) => [
    for (final row in rows)
      FacilityFormEntry(
        name: row.nameController.text.trim(),
        address: row.addressController.text.trim(),
        confirmed: row.confirmed,
      ),
  ];

  void _addRow(List<_FacilityRow> rows) =>
      setState(() => rows.add(_FacilityRow()));

  void _removeRow(List<_FacilityRow> rows, _FacilityRow row) {
    row.dispose();
    setState(() => rows.remove(row));
  }

  /// 한 행의 주소를 좌표로 변환해 확인 상태를 갱신한다.
  Future<void> _checkRow(_FacilityRow row) async {
    final address = row.addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('주소를 먼저 입력해 주세요.')));
      return;
    }

    setState(() => row.status = _CheckStatus.checking);

    try {
      final candidates = await Services.instance.geo.geocode(address);
      if (!mounted) return;

      setState(() {
        if (candidates.isEmpty) {
          // 빈 결과 = 주소를 못 찾음. 주소를 고쳐야 한다.
          row.confirmed = null;
          row.status = _CheckStatus.notFound;
        } else {
          final top = candidates.first;
          row.confirmed = CourseFacility(
            address: address,
            lat: top.lat,
            lng: top.lng,
          );
          row.status = _CheckStatus.confirmed;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => row.status = _CheckStatus.error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 등록일 때만 GPX 파일이 필요하다. 수정은 경로를 바꾸지 않는다.
    final file = _pickedFile;
    if (!_isEdit && file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GPX 파일을 선택해 주세요.')));
      return;
    }

    // 좌표 미확인 시설이 있으면 여기서 막는다(제출 전에).
    final List<CourseFacility> parkings;
    final List<CourseFacility> restrooms;
    try {
      parkings = collectFacilities(_entries(_parkingRows), label: '주차장');
      restrooms = collectFacilities(_entries(_restroomRows), label: '화장실');
    } on FacilityInputException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    setState(() => _submitting = true);

    try {
      if (_isEdit) {
        final course = await Services.instance.course.updateCourse(
          courseId: widget.existing!.id,
          name: _nameController.text.trim(),
          distanceKm: int.parse(_distanceController.text.trim()),
          difficulty: _difficulty,
          address: _addressController.text.trim(),
          tags: _optional(_tagsController),
          parkings: parkings,
          restrooms: restrooms,
          description: _optional(_descriptionController),
        );
        if (!mounted) return;
        // 수정한 코스를 호출한 화면에 돌려준다(지도/목록이 갱신하도록).
        Navigator.of(context).pop(course);
      } else {
        final bytes = await file!.readAsBytes();
        final course = await Services.instance.course.uploadGpxFile(
          bytes: bytes,
          filename: file.name,
          name: _nameController.text.trim(),
          distanceKm: int.parse(_distanceController.text.trim()),
          difficulty: _difficulty,
          address: _addressController.text.trim(),
          tags: _optional(_tagsController),
          parkings: parkings,
          restrooms: restrooms,
          description: _optional(_descriptionController),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(courseId: course.id),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _pickedFile;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(_isEdit ? '코스 수정' : 'GPX로 코스 등록')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '코스 이름',
                hintText: '예) No10. 사계 해안도로',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '코스 이름을 입력해 주세요' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '거리 (왕복 기준)',
                hintText: '예) 6',
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null) return '거리를 km 단위 정수로 입력해 주세요';
                if (parsed < 1) return '거리는 1km 이상이어야 해요';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '예) 송악산 주차장 서귀포시 대정읍 상모리 4165-123',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '주소를 입력해 주세요' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: '태그 (선택)',
                hintText: '쉼표로 구분 — 예) 해안도로,서쪽,서귀포',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            _buildFacilitySection(
              title: '근처 주차장',
              icon: Icons.local_parking_outlined,
              rows: _parkingRows,
              label: '주차장',
            ),
            const SizedBox(height: 20),
            _buildFacilitySection(
              title: '근처 화장실',
              icon: Icons.wc_outlined,
              rows: _restroomRows,
              label: '화장실',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '코스 소개 (선택)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '난이도',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<CourseDifficulty>(
              segments: [
                for (final difficulty in CourseDifficulty.values)
                  ButtonSegment(
                    value: difficulty,
                    label: Text(difficulty.label),
                  ),
              ],
              selected: {_difficulty},
              onSelectionChanged: (selection) =>
                  setState(() => _difficulty = selection.first),
            ),
            // 수정 모드에선 경로(GPX)를 바꾸지 않으므로 파일 칸을 숨긴다.
            if (!_isEdit) ...[
            const SizedBox(height: 20),
            const Text(
              'GPX 파일',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      file == null
                          ? Icons.upload_file_rounded
                          : Icons.route_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file?.name ?? '선택된 파일 없음',
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (file != null)
                            Text(
                              '${(file.size / 1024).toStringAsFixed(0)} KB',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _submitting ? null : _pickFile,
                      // 전역 OutlinedButton 테마의 minimumSize는 화면 폭 전체를
                      // 채우는 버튼(Size.fromHeight)을 기준으로 잡혀 있다. 이 버튼은
                      // Row 안에 Expanded 없이 놓이므로 그 값을 그대로 물려받으면
                      // 무한 너비를 요구해 레이아웃이 깨진다. 여기서만 좁게 되돌린다.
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(file == null ? '파일 선택' : '변경'),
                    ),
                  ],
                ),
              ),
            ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? (_isEdit ? '저장 중...' : '등록 중...')
                    : (_isEdit ? '수정 완료' : '코스 등록하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacilitySection({
    required String title,
    required IconData icon,
    required List<_FacilityRow> rows,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _submitting ? null : () => _addRow(rows),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('추가'),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final row in rows) _buildFacilityRow(rows, row, label),
      ],
    );
  }

  Widget _buildFacilityRow(
    List<_FacilityRow> rows,
    _FacilityRow row,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: row.nameController,
                      decoration: const InputDecoration(
                        labelText: '이름 (선택)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: row.addressController,
                      decoration: InputDecoration(
                        labelText: '$label 주소',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        // 주소를 고치면 직전 확인 좌표는 더 이상 맞지 않는다.
                        if (row.status != _CheckStatus.idle) {
                          setState(() {
                            row.confirmed = null;
                            row.status = _CheckStatus.idle;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _submitting ? null : () => _removeRow(rows, row),
                icon: const Icon(Icons.close),
                tooltip: '삭제',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton(
                onPressed: (_submitting || row.status == _CheckStatus.checking)
                    ? null
                    : () => _checkRow(row),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: row.status == _CheckStatus.checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('확인'),
              ),
              const SizedBox(width: 10),
              Expanded(child: _statusLabel(row)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusLabel(_FacilityRow row) {
    switch (row.status) {
      case _CheckStatus.confirmed:
        return const Text(
          '✓ 좌표 확인됨',
          style: TextStyle(color: Colors.green, fontSize: 12),
        );
      case _CheckStatus.notFound:
        return const Text(
          '올바른 도로명 주소를 입력해 주세요',
          style: TextStyle(color: Colors.red, fontSize: 12),
        );
      case _CheckStatus.error:
        return const Text(
          '확인 실패 — 다시 시도해 주세요',
          style: TextStyle(color: Colors.red, fontSize: 12),
        );
      case _CheckStatus.idle:
      case _CheckStatus.checking:
        return const SizedBox.shrink();
    }
  }
}

/// 편의시설 주소 확인 상태.
enum _CheckStatus { idle, checking, confirmed, notFound, error }

/// 등록 폼의 편의시설 입력 한 줄이 들고 있는 상태(컨트롤러 + 확인 결과).
class _FacilityRow {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  /// "확인"으로 확보한 좌표. 주소를 고치면 null로 되돌린다.
  CourseFacility? confirmed;
  _CheckStatus status = _CheckStatus.idle;

  void dispose() {
    nameController.dispose();
    addressController.dispose();
  }
}
