package com.example.demo.repository;

import com.example.demo.domain.PacketMeta;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@Repository
public interface PacketMetaRepository extends JpaRepository<PacketMeta, UUID> {

    @Query(value = """
            select date_trunc('second', p.start_time) as bucket,
                   sum(coalesce(p.pps, 0)) as pps_sum,
                   sum(coalesce(p.bps, 0)) as bps_sum
            from packet_meta p
            where (p.src_ip = :ip or p.dst_ip = :ip)
              and p.start_time > :since
            group by bucket
            order by bucket asc
            """, nativeQuery = true)
    List<TrafficBucketRow> findBucketedTraffic(
            @Param("ip") String ip,
            @Param("since") OffsetDateTime since
    );

    @Query("""
            select p from PacketMeta p
            where (p.srcIp = :ip or p.dstIp = :ip)
              and p.startTime >= :since
            order by p.startTime asc
            """)
    List<PacketMeta> findRecentByIp(
            @Param("ip") String ip,
            @Param("since") OffsetDateTime since,
            Pageable pageable
    );

    interface TrafficBucketRow {
        OffsetDateTime getBucket();
        Double getPpsSum();
        Double getBpsSum();
    }
}
