package com.example.demo.service;

import com.example.demo.domain.User;
import com.example.demo.dto.SimpleMessageResponseDto;
import com.example.demo.dto.user.JwtResponseDto;
import com.example.demo.dto.user.LoginRequestDto;
import com.example.demo.dto.user.SignUpRequestDto;
import com.example.demo.repository.UserRepository;
import com.example.demo.security.JwtTokenProvider;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider jwtTokenProvider;

    @Transactional
    public SimpleMessageResponseDto signup(SignUpRequestDto req) {
        if (userRepository.existsByEmail(req.getEmail())) {
            throw new IllegalArgumentException("이미 존재하는 이메일입니다.");
        }

        User user = User.create(
                req.getEmail(),
                passwordEncoder.encode(req.getPassword()),
                req.getName(), 
                OffsetDateTime.now()
        );
        userRepository.save(user);

        return SimpleMessageResponseDto.of("회원가입을 성공했습니다. 로그인 후 이용해주세요.");
    }

    @Transactional(readOnly = true)
    public JwtResponseDto login(LoginRequestDto req) {
        User user = userRepository.getByEmail(req.getEmail());
        if (!passwordEncoder.matches(req.getPassword(), user.getPassword())) {
            throw new IllegalArgumentException("비밀번호가 틀렸습니다.");
        }
        return buildJwtResponse(user);
    }

    private JwtResponseDto buildJwtResponse(User user) {
        String token = jwtTokenProvider.generateToken(user);
        return JwtResponseDto.of(token);
    }
}
