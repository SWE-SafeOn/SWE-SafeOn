package com.example.demo.repository;

import com.example.demo.domain.UserDevice;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserDeviceRepository extends JpaRepository<UserDevice, UUID> {
    List<UserDevice> findAllByUserUserId(UUID userId);

    Optional<UserDevice> findByDeviceDeviceIdAndUserUserId(UUID deviceId, UUID userId);

    long countByUserUserId(UUID userId);

    List<UserDevice> findAllByDeviceDeviceId(UUID deviceId);

    Optional<UserDevice> findFirstByDeviceDeviceId(UUID deviceId);

    default UserDevice getByDeviceAndUser(UUID deviceId, UUID userId) {
        return findByDeviceDeviceIdAndUserUserId(deviceId, userId)
                .orElseThrow(() -> new EntityNotFoundException("해당 사용자와 디바이스가 연결되지 않았습니다."));
    }

    default UserDevice getFirstByDevice(UUID deviceId) {
        return findFirstByDeviceDeviceId(deviceId)
                .orElseThrow(() -> new EntityNotFoundException("디바이스 연결 정보를 찾을 수 없습니다."));
    }
}
