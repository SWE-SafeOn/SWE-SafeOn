package com.example.demo.security;

import com.example.demo.domain.User;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

@Component
public class JwtTokenProvider {

    private final Key signingKey;
    private final long validityInMs;

    public JwtTokenProvider(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.expiration-ms:3600000}") long validityInMs
    ) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.validityInMs = validityInMs;
    }

    public String generateToken(User user) {
        Instant now = Instant.now();
        Instant expiry = now.plusMillis(validityInMs);
        return Jwts.builder()
                .setSubject(user.getUserId().toString())
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(expiry))
                .claim("userId", user.getUserId().toString())
                .claim("email", user.getEmail())
                .claim("name", user.getName())
                .signWith(signingKey, SignatureAlgorithm.HS256)
                .compact();
    }

    public boolean validateToken(String token) {
        try {
            getClaims(token);
            return true;
        } catch (Exception ex) {
            return false;
        }
    }

    public AuthenticatedUser getAuthenticatedUser(String token) {
        Claims claims = getClaims(token);
        String userId = claims.get("userId", String.class);
        UUID userUuid = userId != null ? UUID.fromString(userId) : UUID.fromString(claims.getSubject());
        String email = claims.get("email", String.class);
        String name = claims.get("name", String.class);
        return new AuthenticatedUser(userUuid, email, name);
    }

    private Claims getClaims(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(signingKey)
                .build()
                .parseClaimsJws(token)
                .getBody();
    }
}
