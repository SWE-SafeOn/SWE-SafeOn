package com.example.demo.repository;

import com.example.demo.domain.PacketMeta;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.UUID;

@Repository
public interface PacketMetaRepository extends JpaRepository<PacketMeta, UUID> {
}
