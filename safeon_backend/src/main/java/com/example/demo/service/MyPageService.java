package com.example.demo.service;

import com.example.demo.domain.User;
import com.example.demo.dto.user.UserResponseDto;
import com.example.demo.dto.user.UserUpdateRequestDto;
import com.example.demo.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@RequiredArgsConstructor
public class MyPageService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional(readOnly = true)
    public UserResponseDto getProfile(UUID userId) {
        User user = getUser(userId);
        return UserResponseDto.from(user);
    }

    @Transactional
    public UserResponseDto updateProfile(UserUpdateRequestDto request, UUID userId) {
        User user = getUser(userId);
        String encodedPassword = request.getPassword() != null && !request.getPassword().isBlank()
                ? passwordEncoder.encode(request.getPassword())
                : null;
        user.updateProfile(request.getName(), encodedPassword);
        return UserResponseDto.from(userRepository.save(user));
    }

    private User getUser(UUID userId) {
        return userRepository.getById(userId);
    }
}
