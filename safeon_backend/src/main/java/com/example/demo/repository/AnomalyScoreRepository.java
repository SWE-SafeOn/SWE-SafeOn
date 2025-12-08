package com.example.demo.repository;

import com.example.demo.domain.AnomalyScore;
import com.example.demo.dto.dashboard.DailyAnomalyCountDto;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface AnomalyScoreRepository extends JpaRepository<AnomalyScore, UUID> {

    @Query("""
            select new com.example.demo.dto.dashboard.DailyAnomalyCountDto(
                cast(a.ts as date),
                count(a)
            )
            from AnomalyScore a
            where a.isAnom = true
              and (:start is null or a.ts >= :start)
              and (:end is null or a.ts < :end)
            group by cast(a.ts as date)
            order by cast(a.ts as date)
            """)
    List<DailyAnomalyCountDto> countDailyAnomalies(
            @Param("start") OffsetDateTime start,
            @Param("end") OffsetDateTime end
    );

    @Query("select max(a.ts) from AnomalyScore a where a.isAnom = false")
    OffsetDateTime findLastNormalTimestamp();

    @Query("""
            select count(a)
            from AnomalyScore a
            where a.isAnom = true
              and a.ts > :since
            """)
    long countAnomaliesSince(@Param("since") OffsetDateTime since);

    long countByIsAnomTrue();

    Optional<AnomalyScore> findByPacketMeta(UUID packetMeta);

    List<AnomalyScore> findTop3ByTsGreaterThanOrderByTsDescScoreIdDesc(OffsetDateTime ts);
}
