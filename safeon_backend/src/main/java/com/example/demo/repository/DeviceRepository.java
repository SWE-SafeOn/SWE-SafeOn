package com.example.demo.repository;

import com.example.demo.domain.Device;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface DeviceRepository extends JpaRepository<Device, UUID> {
    Optional<Device> findByDeviceId(UUID deviceId);

    java.util.List<Device> findAllByDiscovered(Boolean discovered);

    default Device getByDeviceId(UUID deviceId) {
        return findByDeviceId(deviceId)
                .orElseThrow(() -> new EntityNotFoundException("디바이스를 찾을 수 없습니다 : " + deviceId));
    }
}
