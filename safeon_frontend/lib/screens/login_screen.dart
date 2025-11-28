import 'package:flutter/material.dart';

import '../models/user_session.dart';
import '../services/safeon_api.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    required this.apiClient,
    this.initialEmail = '',
    this.initialPassword = '',
    this.initialNickname = '',
  });

  final void Function(UserSession session, String password) onLoginSuccess;
  final SafeOnApiClient apiClient;
  final String initialEmail;
  final String initialPassword;
  final String initialNickname;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _acceptTerms = false;
  String? _savedNickname;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
    _passwordController.text = widget.initialPassword;
    if (widget.initialNickname.isNotEmpty) {
      _savedNickname = widget.initialNickname;
      _nicknameController.text = widget.initialNickname;
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEmail != widget.initialEmail) {
      _emailController.text = widget.initialEmail;
    }
    if (oldWidget.initialPassword != widget.initialPassword) {
      _passwordController.text = widget.initialPassword;
    }
    if (oldWidget.initialNickname != widget.initialNickname) {
      if (widget.initialNickname.isNotEmpty) {
        _savedNickname = widget.initialNickname;
        _nicknameController.text = widget.initialNickname;
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _acceptTerms = false;
      if (!_isLoginMode && _savedNickname != null) {
        _nicknameController.text = _savedNickname!;
      }
    });
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_isLoginMode && !_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('계정을 생성하려면 약관에 동의해야 합니다.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_isLoginMode) {
        final token = await widget.apiClient.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        final profile = await widget.apiClient.fetchProfile(token);
        if (!mounted) return;
        _savedNickname = profile.name;
        messenger.showSnackBar(
          const SnackBar(content: Text('로그인에 성공했어요!')),
        );

        widget.onLoginSuccess(
          UserSession(token: token, profile: profile),
          _passwordController.text,
        );
      } else {
        if (_passwordController.text != _confirmPasswordController.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')),
          );
          return;
        }

        final nickname = _nicknameController.text.trim();

        await widget.apiClient.signup(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: nickname.isNotEmpty
              ? nickname
              : _deriveNicknameFromEmail(_emailController.text),
        );

        if (!mounted) return;
        _savedNickname = nickname;
        messenger.showSnackBar(
          const SnackBar(content: Text('회원가입이 완료되었습니다. 로그인해주세요.')),
        );
        setState(() {
          _isLoginMode = true;
          _acceptTerms = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('요청 처리 중 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _deriveNicknameFromEmail(String email) {
    final trimmed = email.trim();
    if (!trimmed.contains('@') || trimmed.startsWith('@')) {
      return 'SafeOn 사용자';
    }
    final candidate = trimmed.split('@').first.trim();
    return candidate.isEmpty ? 'SafeOn 사용자' : candidate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F1D3B),
              Color(0xFF12295F),
              SafeOnColors.primary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLoginMode ? 'SafeOn에 로그인' : 'SafeOn 계정 만들기',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isLoginMode
                          ? '스마트 홈을 안전하게 관리하려면 로그인이 필요해요.'
                          : '몇 가지 정보만 입력하면 손쉽게 가입할 수 있어요.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 10,
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: '이메일',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '이메일을 입력해주세요.';
                                  }
                                  if (!value.contains('@')) {
                                    return '유효한 이메일을 입력해주세요.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: '비밀번호',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '비밀번호를 입력해주세요.';
                                  }
                                  if (value.length < 8) {
                                    return '비밀번호는 8자 이상이어야 합니다.';
                                  }
                                  return null;
                                },
                              ),
                              if (!_isLoginMode) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _nicknameController,
                                  decoration: const InputDecoration(
                                    labelText: '닉네임',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  validator: (value) {
                                    if (_isLoginMode) {
                                      return null;
                                    }
                                    if (value == null || value.trim().isEmpty) {
                                      return '사용할 닉네임을 입력해주세요.';
                                    }
                                    if (value.trim().length < 2) {
                                      return '닉네임은 2자 이상이어야 합니다.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  decoration: const InputDecoration(
                                    labelText: '비밀번호 확인',
                                    prefixIcon: Icon(Icons.lock_reset_outlined),
                                  ),
                                  obscureText: _obscurePassword,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '비밀번호를 다시 입력해주세요.';
                                    }
                                    if (value.length < 8) {
                                      return '비밀번호는 8자 이상이어야 합니다.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                CheckboxListTile(
                                  value: _acceptTerms,
                                  onChanged: (value) {
                                    setState(() => _acceptTerms = value ?? false);
                                  },
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('서비스 이용약관 및 개인정보 처리방침에 동의합니다.'),
                                ),
                              ],
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _submit,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 52),
                                  backgroundColor: SafeOnColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(Colors.white),
                                        ),
                                      )
                                    : Text(_isLoginMode ? '로그인' : '회원가입'),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _toggleMode,
                                child: Text(
                                  _isLoginMode
                                      ? '계정이 없으신가요? 지금 회원가입'
                                      : '이미 계정이 있으신가요? 로그인',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
