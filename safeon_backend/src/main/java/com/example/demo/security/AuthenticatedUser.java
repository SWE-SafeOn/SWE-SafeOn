package com.example.demo.security;

import java.util.UUID;

/**
 * Lightweight principal exposed via {@code @AuthenticationPrincipal}.
 */
public record AuthenticatedUser(
        UUID userId,
        String email,
        String name
) {
}
