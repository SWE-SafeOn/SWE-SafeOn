package com.example.demo.domain;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class User {

    @Id
    @Column(name = "user_id")
    @GeneratedValue(generator = "uuid2")
    private UUID userId;

    @Column(unique = true, nullable = false)
    private String email;

    @Column(nullable = false)
    private String password;

    private String name;

    @Column(name = "registered_at")
    private OffsetDateTime registeredAt;

    public static User create(String email, String password, String name, OffsetDateTime registeredAt) {
        User user = new User();
        user.email = email;
        user.password = password;
        user.name = name;
        user.registeredAt = registeredAt;
        return user;
    }

    public void updateProfile(String name, String password) {
        if (name != null) {
            this.name = name;
        }
        if (password != null) {
            this.password = password;
        }
    }
}
