package com.example.demo.dto.user;

public record JwtResponseDto(String accessToken) {
    public static JwtResponseDto of(String token) {
        return new JwtResponseDto(token);
    }
}
