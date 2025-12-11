package com.example.demo.repository;

import com.example.demo.domain.UserAlert;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.data.jpa.repository.JpaRepository;

import com.example.demo.dto.dashboard.DailyAnomalyCountDto;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
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

    @Query("""
            select new com.example.demo.dto.dashboard.DailyAnomalyCountDto(
                cast(ua.notifiedAt as date),
                count(ua)
            )
            from UserAlert ua
            where ua.user.userId = :userId
              and ua.notifiedAt is not null
              and (:start is null or ua.notifiedAt >= :start)
              and (:end is null or ua.notifiedAt < :end)
            group by cast(ua.notifiedAt as date)
            order by cast(ua.notifiedAt as date)
            """)
    List<DailyAnomalyCountDto> countDailyAlerts(
            @Param("userId") UUID userId,
            @Param("start") OffsetDateTime start,
            @Param("end") OffsetDateTime end
    );
}
