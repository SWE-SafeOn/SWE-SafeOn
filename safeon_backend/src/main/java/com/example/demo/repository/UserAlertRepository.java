package com.example.demo.repository;

import com.example.demo.domain.UserAlert;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserAlertRepository extends JpaRepository<UserAlert, UUID> {
    List<UserAlert> findByUserUserIdOrderByNotifiedAtDesc(UUID userId);

    long countByUserUserId(UUID userId);

    Optional<UserAlert> findByUserUserIdAndAlertAlertId(UUID userId, UUID alertId);

    Optional<UserAlert> findFirstByUserUserIdOrderByNotifiedAtDesc(UUID userId);

    default UserAlert getByUserUserIdAndAlertAlertId(UUID userId, UUID alertId) {
        return findByUserUserIdAndAlertAlertId(userId, alertId)
                .orElseThrow(() -> new EntityNotFoundException("해당 사용자와 연관된 알림이 없습니다."));
    }
}
