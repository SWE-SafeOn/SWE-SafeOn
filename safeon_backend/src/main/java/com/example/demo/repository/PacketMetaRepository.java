package com.example.demo.repository;

import com.example.demo.domain.PacketMeta;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.UUID;

@Repository
public interface PacketMetaRepository extends JpaRepository<PacketMeta, UUID> {

    @Query("""
            select p from PacketMeta p
            where (p.srcIp = :ip or p.dstIp = :ip)
              and p.startTime >= :since
            order by p.startTime asc
            """)
    java.util.List<PacketMeta> findRecentByIp(String ip, OffsetDateTime since, Pageable pageable);
}
