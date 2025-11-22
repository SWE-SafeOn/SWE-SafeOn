package com.example.demo.dto.user;

import com.example.demo.domain.User;
import lombok.Builder;

@Builder
public record UserResponseDto(
        String id,
        String email,
        String name,
        String registeredAt
) {
    public static UserResponseDto from(User user) {
        return UserResponseDto.builder()
                .id(user.getUserId().toString())
                .email(user.getEmail())
                .name(user.getName())
                .registeredAt(user.getRegisteredAt() != null ? user.getRegisteredAt().toString() : null)
                .build();
    }
}
