import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/home_banner.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';

/// 배너 이미지 등록/삭제 화면.
///
/// 여러 장을 한 번에 고르고, 등록 시 순서대로 하나씩 업로드한다(서버는 파일
/// 1개짜리 POST /banners만 받는다 — 배치 엔드포인트는 없다). 일부만 실패해도
/// 성공한 항목은 목록에서 지우고 실패한 것만 남겨서 다시 시도할 수 있게 한다.
///
/// 이미 등록된 배너 목록도 같은 화면에서 보여주고 지울 수 있다 — 별도
/// "배너 관리" 화면을 새로 만드는 대신, 어차피 관리자만 들어오는 이 화면에
/// 얹는 편이 화면 하나를 덜 늘린다.
///
/// 진입 버튼은 [AdminOnly]로 admin에게만 보이고, 제출/삭제는 서버가
/// `require_admin`으로 막는다(notice_create_screen.dart와 같은 방식) — 화면
/// 자체엔 권한 검사를 두지 않는다.
class BannerCreateScreen extends StatefulWidget {
  const BannerCreateScreen({super.key});

  @override
  State<BannerCreateScreen> createState() => _BannerCreateScreenState();
}

class _PickedImage {
  _PickedImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  /// 마지막 업로드 시도가 실패했을 때만 채워진다.
  String? error;
}

class _BannerCreateScreenState extends State<BannerCreateScreen> {
  final List<_PickedImage> _items = [];
  bool _submitting = false;
  int _uploadedCount = 0;

  late Future<List<HomeBanner>> _existingFuture;
  // 삭제 중인 배너 id들. 버튼 중복 클릭 막고, 실패 시 원래 목록으로 되돌리는 기준.
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _existingFuture = Services.instance.banner.loadBanners();
  }

  Future<void> _deleteExisting(HomeBanner banner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('배너를 삭제할까요?'),
        content: const Text('삭제하면 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting.add(banner.id));
    try {
      await Services.instance.banner.deleteBanner(banner.id);
      if (!mounted) return;
      setState(() {
        _existingFuture = _existingFuture.then(
          (banners) => banners.where((b) => b.id != banner.id).toList(),
        );
        _deleting.remove(banner.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting.remove(banner.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pickImages() async {
    // pickFiles는 이 버전에서 기본이 다중 선택이다(allowMultiple 기본값 true).
    final result = await FilePicker.pickFiles(type: FileType.image);
    final files = result?.files;
    if (files == null || files.isEmpty) return;

    final picked = <_PickedImage>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      picked.add(_PickedImage(name: file.name, bytes: bytes));
    }

    if (!mounted) return;
    setState(() => _items.addAll(picked));
  }

  void _removeAt(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _submit() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미지를 선택해 주세요.')));
      return;
    }

    setState(() {
      _submitting = true;
      _uploadedCount = 0;
    });

    // 실패한 것만 남기고 성공한 건 목록에서 지운다 — 재시도할 때 다시 다
    // 올릴 필요 없이 실패분만 다시 누르면 되게.
    final remaining = <_PickedImage>[];
    final uploaded = <HomeBanner>[];
    for (final item in _items) {
      try {
        uploaded.add(
          await Services.instance.banner.uploadBanner(
            bytes: item.bytes,
            filename: item.name,
          ),
        );
      } catch (e) {
        item.error = '$e';
        remaining.add(item);
      }
      if (!mounted) return;
      setState(() => _uploadedCount++);
    }

    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(remaining);
      _submitting = false;
      if (uploaded.isNotEmpty) {
        _existingFuture = _existingFuture.then(
          (banners) => [...banners, ...uploaded],
        );
      }
    });

    if (remaining.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${remaining.length}개 업로드에 실패했어요. 다시 시도해 주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('배너 등록')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            '등록된 배너',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<HomeBanner>>(
            future: _existingFuture,
            builder: (context, snapshot) {
              final banners = snapshot.data;
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: _tileSize,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (banners == null || banners.isEmpty) {
                return Text(
                  '아직 등록된 배너가 없어요',
                  style: TextStyle(
                    color: AppColors.ink.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final banner in banners)
                    _ExistingBannerTile(
                      banner: banner,
                      deleting: _deleting.contains(banner.id),
                      onDelete: () => _deleteExisting(banner),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Text(
            _items.isEmpty ? '이미지를 선택해 주세요' : '${_items.length}장 선택됨',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _items.length; i++)
                _ImageTile(item: _items[i], onRemove: () => _removeAt(i)),
              _AddTile(onTap: _submitting ? null : _pickImages),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? '업로드 중... ($_uploadedCount/${_items.length})'
                    : _items.isEmpty
                    ? '등록하기'
                    : '${_items.length}장 등록하기',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _tileSize = 100.0;

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.item, required this.onRemove});

  final _PickedImage item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _tileSize,
      height: _tileSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: _tileSize,
              height: _tileSize,
              color: AppColors.ink.withValues(alpha: 0.06),
              child: Image.memory(item.bytes, fit: BoxFit.cover),
            ),
          ),
          if (item.error != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          Positioned(
            top: -8,
            right: -8,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExistingBannerTile extends StatelessWidget {
  const _ExistingBannerTile({
    required this.banner,
    required this.deleting,
    required this.onDelete,
  });

  final HomeBanner banner;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _tileSize,
      height: _tileSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: _tileSize,
              height: _tileSize,
              color: AppColors.ink.withValues(alpha: 0.06),
              child: Image.network(
                banner.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          if (deleting)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (!deleting)
            Positioned(
              top: -8,
              right: -8,
              child: InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _tileSize,
        height: _tileSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.ink.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: AppColors.ink.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
