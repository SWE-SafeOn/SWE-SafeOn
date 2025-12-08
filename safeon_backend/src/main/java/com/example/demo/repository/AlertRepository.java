package com.example.demo.repository;

import com.example.demo.domain.Alert;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface AlertRepository extends JpaRepository<Alert, UUID> {
    Optional<Alert> findByAlertId(UUID alertId);

    boolean existsByTsAfter(OffsetDateTime ts);

    @Query("select max(a.ts) from Alert a where a.ts <= :before")
    OffsetDateTime findLatestAlertTimestampBefore(@Param("before") OffsetDateTime before);

    default Alert getByAlertId(UUID alertId) {
        return findByAlertId(alertId)
                .orElseThrow(() -> new EntityNotFoundException("알림을 찾을 수 없습니다 : " + alertId));
    }
}
