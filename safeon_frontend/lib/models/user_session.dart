import 'user_profile.dart';

class UserSession {
  const UserSession({required this.token, required this.profile});

  final String token;
  final UserProfile profile;

  UserSession copyWith({UserProfile? profile}) {
    return UserSession(token: token, profile: profile ?? this.profile);
  }
}