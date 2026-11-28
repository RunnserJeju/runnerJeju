import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../exceptions/app_exception.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/confirm_popup.dart';
import '../../widgets/profile_avatar.dart';
import '../auth/login_screen.dart';

/// 회원 정보: 맨 위 프로필 사진(누르면 바꾸기), 닉네임(누르면 바꾸기)·이메일·가입일,
/// 맨 아래 작은 회원탈퇴.
class MemberInfoScreen extends StatefulWidget {
  const MemberInfoScreen({super.key});

  @override
  State<MemberInfoScreen> createState() => _MemberInfoScreenState();
}

class _MemberInfoScreenState extends State<MemberInfoScreen> {
  late Future<User?> _future = _load();

  /// 사진을 올리거나 지우는 중. 그동안 사진 위에 스피너를 띄우고 다시 누르지 못하게 한다.
  bool _savingImage = false;

  Future<User?> _load() =>
      Services.instance.auth.loadCurrentUser(refresh: true);

  /// 서버가 받는 한도(8MB) 안쪽으로 줄여서 올린다. 원 안에 작게 보이므로 1024px면 충분하다.
  static const double _maxImageSide = 1024;

  Future<void> _editImage(User? user) async {
    if (_savingImage) return;
    final hasImage = user?.profileImageUrl != null;
    final action = await showDialog<_ImageAction>(
      context: context,
      builder: (dialogContext) => PopupFrame(
        title: '프로필 사진',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PopupButton(
              label: '앨범에서 선택',
              primary: true,
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ImageAction.pick),
            ),
            if (hasImage) ...[
              const SizedBox(height: 8),
              PopupButton(
                label: '기본 이미지로 변경',
                danger: true,
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_ImageAction.remove),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    String? path;
    if (action == _ImageAction.pick) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxImageSide,
        maxHeight: _maxImageSide,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      path = picked.path;
    }

    setState(() => _savingImage = true);
    try {
      final auth = Services.instance.auth;
      final updated = path == null
          ? await auth.removeProfileImage()
          : await auth.updateProfileImage(path);
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
      });
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  Future<void> _editNickname(User? user) async {
    final nickname = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initial: user?.nickname ?? ''),
    );
    if (nickname == null || nickname == user?.nickname || !mounted) return;

    try {
      final updated = await Services.instance.auth.changeNickname(nickname);
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
      });
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _withdraw() async {
    final confirmed = await showConfirmPopup(
      context,
      title: '정말 탈퇴할까요?',
      message:
          '계정 정보(이메일·닉네임·프로필)와 러닝 경로가 삭제되고, '
          '완주 스탬프와 찜 목록은 복구할 수 없어요.\n'
          '같은 계정으로 다시 로그인하면 새 계정으로 시작해요.',
      cancelLabel: '취소',
      confirmLabel: '탈퇴하기',
      danger: true,
    );
    if (confirmed != true || !mounted) return;

    try {
      await Services.instance.auth.withdraw();
      // 기기 토큰은 서버가 탈퇴 때 지운다. 여기서는 수신만 멈춘다.
      await Services.instance.push.stop();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'login'),
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('회원 정보')),
      body: FutureBuilder<User?>(
        future: _future,
        builder: (context, snapshot) => AsyncView<User?>(
          snapshot: snapshot,
          onRetry: () => setState(() {
            _future = _load();
          }),
          builder: (context, user) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const SizedBox(height: 8),
              Center(
                child: _EditableAvatar(
                  imageUrl: user?.profileImageUrl,
                  saving: _savingImage,
                  onTap: () => _editImage(user),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Column(
                  children: [
                    _InfoRow(
                      label: '닉네임',
                      value: user?.nickname,
                      onTap: () => _editNickname(user),
                    ),
                    const Divider(height: 1, color: AppColors.lineSoft),
                    _InfoRow(label: '이메일', value: user?.email),
                    const Divider(height: 1, color: AppColors.lineSoft),
                    _InfoRow(
                      label: '가입일',
                      value: user?.createdAt == null
                          ? null
                          : Formatters.date(user!.createdAt!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              // 스토어 정책(계정 삭제 제공)용. 눈에 띄지 않게 작은 텍스트로.
              Center(
                child: TextButton(
                  onPressed: _withdraw,
                  style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                  child: const Text(
                    '회원탈퇴',
                    style: TextStyle(
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onTap});

  final String label;
  final String? value;

  /// 주면 누를 수 있는 줄이 되고 오른쪽에 화살표가 붙는다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap == null) return _content();

    return Semantics(
      button: true,
      label: '$label 바꾸기',
      child: InkWell(onTap: onTap, child: _content()),
    );
  }

  Widget _content() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.textSubtle),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textSubtle,
            ),
          ],
        ],
      ),
    );
  }
}

/// 닉네임 입력창. 저장을 누르면 앞뒤 공백을 뗀 값을 돌려준다.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final _formKey = GlobalKey<FormState>();

  // 서버 한도(NicknameUpdate)와 같다.
  static const int _maxLength = 20;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return PopupFrame(
      title: '닉네임 바꾸기',
      cancelLabel: '취소',
      confirmLabel: '저장',
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _submit,
      child: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: _maxLength,
          decoration: const InputDecoration(hintText: '예) 제주러너'),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? '닉네임을 입력해 주세요'
              : null,
        ),
      ),
    );
  }
}

enum _ImageAction { pick, remove }

/// 큰 프로필 사진 + 오른쪽 아래 카메라 배지. 누르면 사진 바꾸기.
class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.imageUrl,
    required this.saving,
    required this.onTap,
  });

  final String? imageUrl;
  final bool saving;
  final VoidCallback onTap;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '프로필 사진 바꾸기',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            children: [
              ProfileAvatar(imageUrl: imageUrl, size: _size),
              if (saving)
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black38,
                  ),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(color: Colors.white),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
